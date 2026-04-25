import AppKit
import Foundation
import Observation
import os
@preconcurrency import Photos

/// 导出阶段对外暴露的进度（PRD 导出页 Step 4）。
/// `phase` 决定文案展示，例如 `.fetchingOriginals` → "下载原图 N/M"。
enum ExportPhase: String {
    case preparing
    case confirming        // 等待用户在写入前确认
    case fetchingOriginals // 仅 Photos 源 → Folder/LR 路径
    case writing           // 调用 destination adapter.export 中
    case cleaning          // Photos App 路径下，处理删除/清理
    case finalizing
}

struct ExportProgress: Equatable {
    var phase: ExportPhase
    var completed: Int
    var total: Int
    var currentName: String?
}

/// 选片页右栏「Smart Group 内全部图」的统一 cell 模型。
/// - `single`：普通单图 cell。
/// - `burst`：连拍组折叠成 1 张代表（角标显示张数）。
enum SmartGroupCell: Identifiable {
    case single(MediaAsset)
    case burst(BurstDisplayGroup)

    var id: UUID {
        switch self {
        case .single(let asset): return asset.id
        case .burst(let burst): return burst.id
        }
    }

    /// 右栏 cell 上展示的封面（连拍组用代表图）。
    var coverAsset: MediaAsset {
        switch self {
        case .single(let asset): return asset
        case .burst(let burst): return burst.coverAsset
        }
    }

    /// 该 cell 是否包含某张资产（用于高亮 / 中央同步）。
    func contains(assetID: UUID) -> Bool {
        switch self {
        case .single(let asset): return asset.id == assetID
        case .burst(let burst): return burst.assets.contains(where: { $0.id == assetID })
        }
    }
}

struct BurstDisplayGroup: Identifiable {
    let id: UUID
    let assets: [MediaAsset]
    let bestAssetID: UUID?

    var coverAsset: MediaAsset {
        if let bestAssetID,
           let bestAsset = assets.first(where: { $0.id == bestAssetID }) {
            return bestAsset
        }
        return assets.first!
    }

    var count: Int {
        assets.count
    }
}

struct BurstSelectionContext {
    let burst: BurstDisplayGroup
    let burstIndex: Int
    let burstCount: Int
    let assetIndex: Int
}

private struct BurstSelectionCacheKey: Equatable {
    let groupID: UUID?
    let assetID: UUID
}

@MainActor
@Observable
final class ProjectStore {
    private let importManager = ImportManager()
    private let importSourceMonitor = ImportSourceMonitor()
    private let logger = Logger(subsystem: "Luma", category: "ProjectStore")
    private let localMLScorer = LocalMLScorer()
    private let videoArchiver = VideoArchiver()
    private let enableImportMonitoring: Bool

    var currentProjectDirectory: URL?
    /// All sessions known in-memory (typically the active project directory’s session).
    var sessions: [Session] = []
    var activeSessionID: UUID?
    /// Stable identifier for the current project manifest.
    /// Set from the loaded manifest and reused on every save so the id never drifts.
    /// Exposed for UI snapshot tooling in the same module; set from manifest on load.
    var currentManifestID: UUID = UUID()
    var projectSummaries: [ProjectSummary] = []
    /// 首页 Session 列表排序键。默认按上次修改。持久化到 UserDefaults。
    var sessionListSort: SessionListSort = .lastModified
    private let sessionListSortDefaultsKey = "Luma.sessionListSort"
    // 历史字段：var photosImportPickerPlan: PhotosImportPlan?
    // 已移除——picker 现在用 AppKit NSAlert 实现，不再走 SwiftUI sheet。
    // 见 AppKitPhotosImportPicker。SwiftUI sheet 在该 SDK 组合下无法稳定承载该 picker。
    /// 当前活跃导入源（USB iPhone / SD 卡）。由 ImportSourceMonitor 推送；UI 据此决定菜单项是否高亮。
    var detectedImportSources: [ImportSourceDescriptor] = []

    private var activeSessionIndex: Int? {
        guard let activeSessionID else { return nil }
        return sessions.firstIndex { $0.id == activeSessionID }
    }

    var currentSession: Session? {
        guard let i = activeSessionIndex else { return nil }
        return sessions[i]
    }

    /// 是否已进入工作区（含仅内存的 UI 预览；无磁盘目录时仍可展示选片界面）。
    var hasActiveProject: Bool {
        currentSession != nil
    }

    var projectName: String {
        get { currentSession?.name ?? "Luma" }
        set {
            guard let i = activeSessionIndex else { return }
            sessions[i].name = newValue
            sessions[i].updatedAt = .now
        }
    }

    var createdAt: Date? {
        get { currentSession?.createdAt }
        set {
            guard let i = activeSessionIndex, let newValue else { return }
            sessions[i].createdAt = newValue
            sessions[i].updatedAt = .now
        }
    }

    var assets: [MediaAsset] {
        get { currentSession?.assets ?? [] }
        set {
            guard let i = activeSessionIndex else { return }
            sessions[i].assets = newValue
            sessions[i].updatedAt = .now
            invalidateDerivedState()
        }
    }

    var groups: [PhotoGroup] {
        get { currentSession?.groups ?? [] }
        set {
            guard let i = activeSessionIndex else { return }
            sessions[i].groups = newValue
            sessions[i].updatedAt = .now
            invalidateDerivedState()
        }
    }
    var selectedGroupID: UUID? {
        didSet { invalidateSelectionDerivedState() }
    }
    var selectedAssetID: UUID? {
        didSet { invalidateSelectionDerivedState() }
    }
    var pendingImportPrompt: PendingImportPrompt?
    /// 照片权限/导入占用的主窗口内 SwiftUI 提示；勿用 `NSAlert`，以免与主界面风格割裂。
    var photosAccessGuidance: PhotosAccessGuidance?
    var recoverableImportSession: ImportSession?
    var importProgress: ImportProgress?
    var isImporting = false
    var lastErrorMessage: String? {
        didSet {
            guard let lastErrorMessage, lastErrorMessage != oldValue else { return }
            RuntimeTrace.error(
                "user_visible_error",
                category: "app",
                metadata: traceContext(["message": lastErrorMessage])
            )
        }
    }
    var isLocalScoring = false
    var localScoringCompleted = 0
    var localScoringTotal = 0
    var localRejectedCount = 0
    var lastSummaryStatus: String?
    var exportOptions: ExportOptions = .default
    var isProjectLibraryPresented = false
    var isPerformanceDiagnosticsPresented = false
    var isExportPanelPresented = false
    var isExporting = false
    var lastExportSummary: String?
    /// 最近一次导出的结构化结果。导出完成后由 `performExport` 设置；
    /// `ContentView` 据此 sheet 弹出 `ExportSummaryView`。
    var lastExportResult: ExportResult?
    /// 实时导出进度，主要给"下载原图 N/M / 写入相册 / 清理"等阶段提供进度条。
    var exportProgress: ExportProgress?
    /// Photos App 路径写入前的二次确认弹窗状态。`true` = 弹窗显示中。
    var isAwaitingPhotosWriteConfirmation: Bool = false
    private var pendingPhotosWriteContinuation: CheckedContinuation<Bool, Never>?

    private var hasBootstrapped = false
    private var isImportMonitoringStarted = false
    private var importPromptQueue: [PendingImportPrompt] = []
    @ObservationIgnored private var derivedStateIsDirty = true
    @ObservationIgnored private var assetLookupCache: [UUID: MediaAsset] = [:]
    @ObservationIgnored private var groupLookupCache: [UUID: PhotoGroup] = [:]
    @ObservationIgnored private var groupSummaryCache: [UUID: GroupDecisionSummary] = [:]
    @ObservationIgnored private var overallSummaryCache: GroupDecisionSummary = .empty
    @ObservationIgnored private var visibleAssetsCacheGroupID: UUID??
    @ObservationIgnored private var visibleAssetsCache: [MediaAsset] = []
    @ObservationIgnored private var visibleBurstGroupsCacheGroupID: UUID??
    @ObservationIgnored private var visibleBurstGroupsCache: [BurstDisplayGroup] = []
    @ObservationIgnored private var selectedBurstContextCacheKey: BurstSelectionCacheKey?
    @ObservationIgnored private var selectedBurstContextCache: BurstSelectionContext?
    private var manifestSaveTask: Task<Void, Never>?
    private var localScoringTask: Task<Void, Never>?
    private var cachePreparationTask: Task<Void, Never>?
    private var groupNameRefreshTask: Task<Void, Never>?
    private let exportOptionsDefaultsKey = "Luma.exportOptions"

    init(enableImportMonitoring: Bool = true) {
        self.enableImportMonitoring = enableImportMonitoring
        loadExportSettings()
        if let raw = UserDefaults.standard.string(forKey: sessionListSortDefaultsKey),
           let sort = SessionListSort(rawValue: raw) {
            sessionListSort = sort
        }
    }

    var selectedAsset: MediaAsset? {
        ensureDerivedState()
        guard let selectedAssetID else { return nil }
        return assetLookupCache[selectedAssetID]
    }

    var visibleAssets: [MediaAsset] {
        ensureDerivedState()
        if visibleAssetsCacheGroupID == selectedGroupID {
            return visibleAssetsCache
        }

        let result: [MediaAsset]
        guard let selectedGroupID,
              let group = groupLookupCache[selectedGroupID] else {
            result = assets
            visibleAssetsCacheGroupID = selectedGroupID
            visibleAssetsCache = result
            return result
        }

        result = group.assets.compactMap { assetLookupCache[$0] }
        visibleAssetsCacheGroupID = selectedGroupID
        visibleAssetsCache = result
        return result
    }

    var selectedGroup: PhotoGroup? {
        ensureDerivedState()
        guard let selectedGroupID else { return nil }
        return groupLookupCache[selectedGroupID]
    }

    var currentImportSessions: [ImportSession] {
        currentSession?.importSessions ?? []
    }

    var importsHubSubtitle: String {
        guard let session = currentSession else { return "尚未创建导入会话" }
        if let last = session.importSessions.last {
            return "\(session.name) · \(last.source.displayName)"
        }
        return "\(session.name) · 尚未有导入记录"
    }

    var scoredCount: Int {
        assets.filter { $0.aiScore != nil }.count
    }

    var cullProcessedCount: Int {
        assets.filter { $0.userDecision != .pending }.count
    }

    var currentPipelineStages: [SessionStageState] {
        let totalAssets = max(assets.count, 1)
        let ingestProgress: Double
        let ingestStatus: SessionStageStatus
        if let progress = importProgress, isImporting || progress.phase == .paused {
            ingestProgress = min(1, Double(progress.completed) / Double(max(progress.total, 1)))
            ingestStatus = progress.phase == .paused ? .failed : .running
        } else if assets.isEmpty {
            ingestProgress = 0
            ingestStatus = .pending
        } else {
            ingestProgress = 1
            ingestStatus = .completed
        }

        let groupingProgress = groups.isEmpty ? (assets.isEmpty ? 0.0 : 0.35) : 1.0
        let groupingStatus: SessionStageStatus = groups.isEmpty
            ? (assets.isEmpty ? .pending : .running)
            : .completed

        let scoreProgress = assets.isEmpty ? 0 : Double(scoredCount) / Double(totalAssets)
        let scoreStatus: SessionStageStatus
        if isLocalScoring {
            scoreStatus = .running
        } else if scoredCount > 0, scoredCount == assets.count {
            scoreStatus = .completed
        } else {
            scoreStatus = .pending
        }

        let cullProgress = assets.isEmpty ? 0 : Double(cullProcessedCount) / Double(totalAssets)
        let cullStatus: SessionStageStatus
        if cullProcessedCount > 0, cullProcessedCount == assets.count {
            cullStatus = .completed
        } else if cullProcessedCount > 0 {
            cullStatus = .running
        } else {
            cullStatus = .pending
        }

        let exportStatus: SessionStageStatus
        if isExporting {
            exportStatus = .running
        } else if lastExportSummary != nil {
            exportStatus = .completed
        } else {
            exportStatus = .pending
        }

        return [
            .init(stage: .ingest, status: ingestStatus, progress: ingestProgress),
            .init(stage: .group, status: groupingStatus, progress: groupingProgress),
            .init(stage: .score, status: scoreStatus, progress: scoreProgress),
            .init(stage: .cull, status: cullStatus, progress: cullProgress),
            .init(stage: .editing, status: .pending, progress: 0),
            .init(stage: .export, status: exportStatus, progress: exportStatus == .completed ? 1 : 0),
        ]
    }

    var visibleBurstGroups: [BurstDisplayGroup] {
        ensureDerivedState()
        if visibleBurstGroupsCacheGroupID == selectedGroupID {
            return visibleBurstGroupsCache
        }

        guard let selectedGroup else {
            visibleBurstGroupsCacheGroupID = selectedGroupID
            visibleBurstGroupsCache = []
            return []
        }

        let sourceSubGroups: [SubGroup]
        if selectedGroup.subGroups.isEmpty {
            sourceSubGroups = selectedGroup.assets.map { assetID in
                SubGroup(id: assetID, assets: [assetID], bestAsset: nil)
            }
        } else {
            sourceSubGroups = selectedGroup.subGroups
        }

        let result: [BurstDisplayGroup] = sourceSubGroups.compactMap { subGroup in
            let burstAssets = subGroup.assets.compactMap { assetLookupCache[$0] }
            guard !burstAssets.isEmpty else { return nil }
            return BurstDisplayGroup(id: subGroup.id, assets: burstAssets, bestAssetID: subGroup.bestAsset)
        }
        visibleBurstGroupsCacheGroupID = selectedGroupID
        visibleBurstGroupsCache = result
        return result
    }

    /// 仅当当前选中图属于「多张连拍」时返回；单张 subGroup 不视为连拍（详情面板不展示 `main.detail.burst`）。
    var selectedBurstContext: BurstSelectionContext? {
        guard let selectedAssetID else { return nil }
        let cacheKey = BurstSelectionCacheKey(groupID: selectedGroupID, assetID: selectedAssetID)
        if selectedBurstContextCacheKey == cacheKey {
            return selectedBurstContextCache
        }

        let bursts = visibleBurstGroups
        guard let burstIndex = bursts.firstIndex(where: { burst in
            burst.assets.contains(where: { $0.id == selectedAssetID })
        }) else {
            selectedBurstContextCacheKey = cacheKey
            selectedBurstContextCache = nil
            return nil
        }

        let burst = bursts[burstIndex]
        guard burst.count > 1 else {
            selectedBurstContextCacheKey = cacheKey
            selectedBurstContextCache = nil
            return nil
        }
        guard let assetIndex = burst.assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return nil
        }

        let context = BurstSelectionContext(
            burst: burst,
            burstIndex: burstIndex,
            burstCount: bursts.count,
            assetIndex: assetIndex
        )
        selectedBurstContextCacheKey = cacheKey
        selectedBurstContextCache = context
        return context
    }

    var pickedCount: Int {
        assets.filter { $0.userDecision == .picked }.count
    }

    var rejectedCount: Int {
        assets.filter { $0.userDecision == .rejected }.count
    }

    var pendingCount: Int {
        assets.count - pickedCount - rejectedCount
    }

    var recommendedCount: Int {
        assets.filter { $0.aiScore?.recommended == true }.count
    }

    var localScoringFraction: Double {
        guard localScoringTotal > 0 else { return 0 }
        return Double(localScoringCompleted) / Double(localScoringTotal)
    }

    var pickedAssetsCount: Int {
        assets.filter { $0.userDecision == .picked }.count
    }

    var canExportPicked: Bool {
        pickedAssetsCount > 0
    }

    var archiveCandidatesCount: Int {
        assets.filter { $0.userDecision != .picked }.count
    }

    /// 当前 session 是否存在源 = 照片 App 的资产。用于决定是否显示「清理源相册」面板。
    var hasPhotosLibrarySources: Bool {
        assets.contains { asset in
            if case .photosLibrary(let id) = asset.source, !id.isEmpty { return true }
            return false
        }
    }

    /// 按当前 `photosCleanupStrategy` 结算：若策略 = `.deleteRejectedOriginals`，返回
    /// 「源 = 照片 App 且 userDecision = rejected」的数量；否则返回 0。给 UI 预览用。
    var photosCleanupPlannedCount: Int {
        guard exportOptions.photosCleanupStrategy == .deleteRejectedOriginals else { return 0 }
        return assets.reduce(into: 0) { count, asset in
            guard asset.userDecision == .rejected else { return }
            if case .photosLibrary(let id) = asset.source, !id.isEmpty {
                count += 1
            }
        }
    }

    /// 「源 = 照片 App 且 userDecision = rejected」的数量（与策略无关，总体可删上限）。
    var photosRejectedFromLibraryCount: Int {
        assets.reduce(into: 0) { count, asset in
            guard asset.userDecision == .rejected else { return }
            if case .photosLibrary(let id) = asset.source, !id.isEmpty {
                count += 1
            }
        }
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        let startedAt = ProcessInfo.processInfo.systemUptime
        RuntimeTrace.startSession(metadata: ["entry": "bootstrap"])
        traceEvent("bootstrap_started", category: "app")

        if let session = importManager.mostRecentRecoverableSession() {
            recoverableImportSession = session
            do {
                let manifest = try importManager.loadManifest(for: session)
                guard let projectDirectory = session.projectDirectory else { return }
                apply(manifest: manifest, in: projectDirectory)
                importProgress = progress(for: session)
            } catch {
                logger.error("Failed to load recoverable session: \(error.localizedDescription, privacy: .public)")
                await loadLastProjectIfAvailable()
            }
            enqueueImportPrompt(.resumeSession(session))
        } else {
            await loadLastProjectIfAvailable()
        }

        refreshProjectSummaries()
        if enableImportMonitoring {
            startImportSourceMonitoring()
        }

        traceMetric(
            "bootstrap_completed",
            category: "app",
            startedAt: startedAt,
            metadata: ["recoverable_session": recoverableImportSession == nil ? "false" : "true"]
        )
    }

    func loadLastProjectIfAvailable() async {
        guard assets.isEmpty else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime

        do {
            guard let projectDirectory = try AppDirectories.projectDirectories().first else { return }
            let data = try Data(contentsOf: AppDirectories.manifestURL(in: projectDirectory))
            let manifest = try JSONDecoder.lumaDecoder.decode(SessionManifest.self, from: data)
            apply(manifest: manifest, in: projectDirectory)
            triggerLocalScoringIfNeeded()
            logger.log("Loaded project \(manifest.name, privacy: .public)")
            traceMetric(
                "last_project_loaded",
                category: "project",
                startedAt: startedAt,
                metadata: [
                    "project_name": manifest.name,
                    "asset_count": String(manifest.assets.count),
                    "group_count": String(manifest.groups.count)
                ]
            )
        } catch {
            logger.error("Failed to load last project: \(error.localizedDescription, privacy: .public)")
            traceError(
                "last_project_load_failed",
                category: "project",
                metadata: ["message": error.localizedDescription]
            )
        }
    }

    func importFolder() async {
        traceEvent("import_requested", category: "import", metadata: ["source": "folder"])
        await runImportOperation { progress, snapshot in
            try await self.importManager.importFolderSelection(progress: progress, snapshot: snapshot)
        }
    }

    func importSDCard() async {
        traceEvent("import_requested", category: "import", metadata: ["source": "sd_card"])
        await runImportOperation { progress, snapshot in
            try await self.importManager.importSDCardSelection(progress: progress, snapshot: snapshot)
        }
    }

    func importIPhone() async {
        traceEvent("import_requested", category: "import", metadata: ["source": "iphone"])
        await runImportOperation { progress, snapshot in
            try await self.importManager.importIPhoneSelection(progress: progress, snapshot: snapshot)
        }
    }

    /// 旧入口（弹 NSAlert 选最近 N 张）。保留供测试与命令行入口；UI 默认走 `presentPhotosImportPicker()`。
    func importPhotosLibrary() async {
        traceEvent("import_requested", category: "import", metadata: ["source": "photos_library"])
        await runImportOperation { progress, snapshot in
            try await self.importManager.importPhotosLibrarySelection(progress: progress, snapshot: snapshot)
        }
    }

    /// 「Mac · 照片 App」— **调试用极简路径**（仅选张数）：
    /// 授权 → 单个 NSAlert（下拉选 N）→ 直接导入；无完整 picker、无 `PhotosImportPlanner.estimate`、无第二段确认。
    /// 全时间范围、`dedupe` 关闭，减少 PhotoKit/模态/回调面，便于对照崩溃（见 `AppKitPhotosCountOnlyPicker`）。
    func presentPhotosImportPicker() async {
        guard !isImporting else {
            traceEvent("photos_import_skipped_busy", category: "import", metadata: [:])
            photosAccessGuidance = .importInProgress
            return
        }
        let flowID = UUID().uuidString
        ImportPathBreadcrumb.mark("photos_import_flow_start", ["flow_id": flowID, "mode": "count_only"])
        let authorized = await ensurePhotosLibraryAuthorization()
        guard authorized else {
            ImportPathBreadcrumb.mark("photos_import_auth_denied", ["flow_id": flowID])
            if photosAccessGuidance == nil { photosAccessGuidance = .accessDenied }
            traceEvent(
                "photos_import_picker_aborted_no_permission",
                category: "import",
                metadata: [
                    "guidance": photosAccessGuidance?.rawValue ?? "nil"
                ]
            )
            return
        }
        ImportPathBreadcrumb.mark("photos_import_auth_ok", ["flow_id": flowID])

        ImportPathBreadcrumb.mark("photos_count_only_modal_before", ["flow_id": flowID])
        guard let limit = AppKitPhotosCountOnlyPicker.presentBlocking() else {
            ImportPathBreadcrumb.mark("photos_picker_cancelled", ["flow_id": flowID, "mode": "count_only"])
            traceEvent("photos_import_picker_outcome_cancelled", category: "import", metadata: ["mode": "count_only"])
            return
        }

        let plan = PhotosImportPlan(
            id: UUID(),
            datePreset: .allTime,
            smartAlbum: nil,
            userAlbumLocalIdentifier: nil,
            userAlbumTitle: nil,
            mediaTypeFilter: .all,
            limit: limit,
            dedupeAgainstCurrentProject: false
        )
        ImportPathBreadcrumb.mark("photos_count_only_confirmed", ["flow_id": flowID, "plan_id": plan.id.uuidString, "limit": String(limit)])
        traceEvent(
            "photos_import_count_only",
            category: "import",
            metadata: [
                "plan_id": plan.id.uuidString,
                "limit": String(limit)
            ]
        )
        await confirmPhotosImport(plan, excludedLocalIdentifiers: [])
    }

    /// 以 `readWrite` 级为准；若系统只给「仅添加」而读图库仍为拒绝，会提示与「无权限」不同的说明。
    private func applyPhotosAuthGuidanceOnFailure(
        readWrite: PHAuthorizationStatus,
        addOnly: PHAuthorizationStatus
    ) {
        if readWrite == .restricted {
            photosAccessGuidance = .accessDenied
            return
        }
        if readWrite == .denied, addOnly == .authorized || addOnly == .limited {
            photosAccessGuidance = .needFullLibraryRead
        } else {
            photosAccessGuidance = .accessDenied
        }
    }

    /// 在状态为 `.notDetermined` 时调用 `requestAuthorization`，会由**系统**弹出 TCC 授权窗（与「旧版」一致）。
    /// 导入需要 `readWrite`；若图库为「仅添加」、读权限仍为 denied，会设置 `needFullLibraryRead`。
    private func ensurePhotosLibraryAuthorization() async -> Bool {
        let readWrite = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let addOnly = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var authMeta: [String: String] = [
            "readwrite": String(readWrite.rawValue),
            "addonly": String(addOnly.rawValue)
        ]
        if let p = Bundle.main.executablePath {
            authMeta["main_executable"] = p
        }
        traceEvent("photos_auth_readwrite_addonly", category: "import", metadata: authMeta)
        if readWrite == .authorized || readWrite == .limited {
            return true
        }
        if readWrite == .denied || readWrite == .restricted {
            applyPhotosAuthGuidanceOnFailure(readWrite: readWrite, addOnly: addOnly)
            return false
        }
        if readWrite == .notDetermined {
            let resolved: PHAuthorizationStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    DispatchQueue.main.async {
                        continuation.resume(returning: newStatus)
                    }
                }
            }
            let addAfter = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            traceEvent(
                "photos_auth_request_result",
                category: "import",
                metadata: [
                    "readwrite": String(resolved.rawValue),
                    "addonly": String(addAfter.rawValue)
                ]
            )
            if resolved == .authorized || resolved == .limited {
                return true
            }
            applyPhotosAuthGuidanceOnFailure(readWrite: resolved, addOnly: addAfter)
            return false
        }
        applyPhotosAuthGuidanceOnFailure(readWrite: readWrite, addOnly: addOnly)
        return false
    }

    /// 从「系统设置」切回 Luma 时调用：若图库已改为允许读，可自动消掉“无权限”提示。
    func refreshPhotosAccessAfterSystemSettings() {
        let rw = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard rw == .authorized || rw == .limited else { return }
        if photosAccessGuidance == .accessDenied || photosAccessGuidance == .needFullLibraryRead {
            photosAccessGuidance = nil
            traceEvent("photos_access_guidance_auto_cleared", category: "import", metadata: ["readwrite": String(rw.rawValue)])
        }
    }

    /// 从「仅张数」或将来完整 picker 确认后，由 `presentPhotosImportPicker()` / 测试调用。
    /// 仍标 `internal`（非 private）以便测试和潜在的命令行入口直接调用。
    func confirmPhotosImport(
        _ plan: PhotosImportPlan,
        excludedLocalIdentifiers: Set<String> = []
    ) async {
        ImportPathBreadcrumb.mark("confirm_photos_import_entry", ["plan_id": plan.id.uuidString])
        traceEvent(
            "import_requested",
            category: "import",
            metadata: [
                "source": "photos_library",
                "limit": String(plan.limit),
                "date_preset": plan.datePreset.label,
                "smart_album": plan.smartAlbumSubtype.map { String($0.rawValue) } ?? "none",
                "user_album": plan.userAlbumLocalIdentifier ?? "none",
                "media": plan.mediaTypeFilter.rawValue,
                "excluded": String(excludedLocalIdentifiers.count)
            ]
        )
        await runImportOperation { progress, snapshot in
            try await self.importManager.importPhotosLibrary(
                plan: plan,
                excludedLocalIdentifiers: excludedLocalIdentifiers,
                progress: progress,
                snapshot: snapshot
            )
        }
    }

    func openProjectLibrary() {
        refreshProjectSummaries()
        isProjectLibraryPresented = true
    }

    func closeProjectLibrary() {
        isProjectLibraryPresented = false
    }

    func openPerformanceDiagnostics() {
        isPerformanceDiagnosticsPresented = true
        traceEvent("performance_diagnostics_opened", category: "diagnostics")
    }

    func closePerformanceDiagnostics() {
        isPerformanceDiagnosticsPresented = false
        traceEvent("performance_diagnostics_closed", category: "diagnostics")
    }

    /// 返回首页 Session 列表前先落盘，再清空内存中的当前项目。
    func leaveProjectToSessionList() {
        traceEvent("leave_project_to_session_list", category: "project")
        persistManifestImmediatelyIfPossible()
        clearCurrentProject()
        refreshProjectSummaries()
    }

    func openProject(_ summary: ProjectSummary) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let manifest = try loadManifest(at: summary.directory)
            apply(manifest: manifest, in: summary.directory)
            refreshProjectSummaries()
            triggerLocalScoringIfNeeded()
            isProjectLibraryPresented = false
            traceMetric(
                "project_opened",
                category: "project",
                startedAt: startedAt,
                metadata: [
                    "project_name": summary.name,
                    "asset_count": String(manifest.assets.count),
                    "group_count": String(manifest.groups.count)
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            traceError(
                "project_open_failed",
                category: "project",
                metadata: [
                    "project_name": summary.name,
                    "message": error.localizedDescription
                ]
            )
        }
    }

    func deleteProject(_ summary: ProjectSummary) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            manifestSaveTask?.cancel()
            localScoringTask?.cancel()

            if urlsReferToSameLocation(currentProjectDirectory, summary.directory) {
                clearCurrentProject()
            }

            if let dir = recoverableImportSession?.projectDirectory,
               urlsReferToSameLocation(dir, summary.directory) {
                recoverableImportSession = nil
                importProgress = nil
            }

            try ImportSessionStore.deleteSessions(forProjectDirectory: summary.directory)
            try FileManager.default.removeItem(at: summary.directory)

            refreshProjectSummaries()

            if currentProjectDirectory == nil, let nextProject = projectSummaries.first {
                openProject(nextProject)
            }

            traceMetric(
                "project_deleted",
                category: "project",
                startedAt: startedAt,
                metadata: ["project_name": summary.name]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshProjectSummaries() {
        do {
            let directories = try AppDirectories.projectDirectories()
            let raw: [ProjectSummary] = directories.map { directory in
                do {
                    let manifest = try loadManifest(at: directory)
                    let assets = manifest.session.assets
                    let decided = assets.filter { $0.userDecision != .pending }.count
                    let exportJobs = manifest.session.exportJobs
                    let lastExport = exportJobs.compactMap(\.completedAt).max()
                    return ProjectSummary(
                        id: directory,
                        directory: directory,
                        name: manifest.name,
                        createdAt: manifest.createdAt,
                        updatedAt: manifest.session.updatedAt,
                        coverImageURL: coverImageURL(from: manifest),
                        state: .ready(assetCount: assets.count, groupCount: manifest.session.groups.count),
                        isCurrent: urlsReferToSameLocation(directory, currentProjectDirectory),
                        decidedCount: decided,
                        totalAssetCount: assets.count,
                        lastExportedAt: lastExport,
                        exportJobCount: exportJobs.count,
                        isArchived: manifest.session.isArchived ?? false
                    )
                } catch {
                    let values = try? directory.resourceValues(forKeys: [.creationDateKey])
                    return ProjectSummary(
                        id: directory,
                        directory: directory,
                        name: directory.lastPathComponent,
                        createdAt: values?.creationDate ?? .distantPast,
                        updatedAt: values?.creationDate ?? .distantPast,
                        coverImageURL: nil,
                        state: .unavailable(reason: error.localizedDescription),
                        isCurrent: urlsReferToSameLocation(directory, currentProjectDirectory),
                        decidedCount: 0,
                        totalAssetCount: 0,
                        lastExportedAt: nil,
                        exportJobCount: 0,
                        isArchived: false
                    )
                }
            }
            projectSummaries = sessionListSort.sort(raw)
        } catch {
            projectSummaries = []
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 软归档：写 manifest 字段；保留磁盘项目，列表里下沉。
    func setArchive(_ summary: ProjectSummary, archived: Bool) {
        do {
            // 当前正在打开的项目可直接改内存 + scheduleManifestSave。
            if urlsReferToSameLocation(summary.directory, currentProjectDirectory),
               let i = activeSessionIndex {
                sessions[i].isArchived = archived
                sessions[i].archivedAt = archived ? .now : nil
                sessions[i].updatedAt = .now
                scheduleManifestSave()
            } else {
                // 否则直接读盘改盘。
                var manifest = try loadManifest(at: summary.directory)
                manifest.session.isArchived = archived
                manifest.session.archivedAt = archived ? .now : nil
                manifest.session.updatedAt = .now
                let url = AppDirectories.manifestURL(in: summary.directory)
                let data = try JSONEncoder.lumaEncoder.encode(manifest)
                try data.write(to: url, options: [.atomic])
            }
            refreshProjectSummaries()
            traceEvent(
                "session_archive_toggled",
                category: "project",
                metadata: [
                    "project_name": summary.name,
                    "archived": archived ? "1" : "0"
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 改变排序后立即重排已有 summaries（不重读盘）。
    func updateSessionListSort(_ sort: SessionListSort) {
        sessionListSort = sort
        projectSummaries = sort.sort(projectSummaries)
        UserDefaults.standard.set(sort.rawValue, forKey: sessionListSortDefaultsKey)
        traceEvent("session_list_sort_changed", category: "project", metadata: ["sort": sort.rawValue])
    }

    private func coverImageURL(from manifest: SessionManifest) -> URL? {
        let assets = manifest.assets
        if let coverID = manifest.session.coverAssetID,
           let cover = assets.first(where: { $0.id == coverID }) {
            return cover.primaryDisplayURL
        }
        return assets.first?.primaryDisplayURL
    }

    func resumeRecoverableImport() async {
        guard let recoverableImportSession else { return }
        await continueImport(recoverableImportSession)
    }

    func acceptPendingImportPrompt() async {
        guard let prompt = pendingImportPrompt else { return }
        pendingImportPrompt = nil
        traceEvent("import_prompt_accepted", category: "import", metadata: ["prompt": prompt.kind])

        switch prompt {
        case .importSource(let source):
            await importDetectedSource(source)
        case .resumeSession(let session):
            await continueImport(session)
        }
    }

    func dismissPendingImportPrompt() {
        if let prompt = pendingImportPrompt {
            traceEvent("import_prompt_dismissed", category: "import", metadata: ["prompt": prompt.kind])
        }
        pendingImportPrompt = nil
        presentNextImportPromptIfPossible()
    }

    func dismissPhotosAccessGuidance() {
        photosAccessGuidance = nil
    }

    func selectGroup(_ groupID: UUID?) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        selectedGroupID = groupID
        // 用右栏 cell 顺序而不是 visibleAssets 顺序选第一张：
        // 1) burst 在前的组会让中央自动进入连拍网格预览（PRD 方案丁的默认行为）；
        // 2) 右栏第一个 cell 自然被高亮，避免「右栏没跟着切组」的视觉错觉。
        if let firstCell = visibleSmartGroupCells.first {
            selectedAssetID = firstCell.coverAsset.id
        } else {
            selectedAssetID = nil
        }
        scheduleRelevantCachePreparation()
        traceMetric(
            "group_selected",
            category: "interaction",
            startedAt: startedAt,
            metadata: [
                "group_id": groupID?.uuidString ?? "all",
                "visible_count": String(selectedGroup?.assets.count ?? assets.count),
                "burst_count": String(selectedGroup?.subGroups.count ?? 0),
                "selected_asset_id": selectedAssetID?.uuidString ?? "none"
            ]
        )
    }

    func selectAsset(_ assetID: UUID) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        selectedAssetID = assetID
        scheduleFocusedAssetCachePreparation()
        traceMetric(
            "asset_selected",
            category: "interaction",
            startedAt: startedAt,
            metadata: ["asset_id": assetID.uuidString]
        )
    }

    func moveSelection(by delta: Int) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let currentAssets = visibleAssets
        guard !currentAssets.isEmpty else { return }

        let currentIndex = currentAssets.firstIndex(where: { $0.id == selectedAssetID }) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), currentAssets.count - 1)
        selectedAssetID = currentAssets[nextIndex].id
        scheduleFocusedAssetCachePreparation()
        traceMetric(
            "selection_moved",
            category: "interaction",
            startedAt: startedAt,
            metadata: [
                "delta": String(delta),
                "asset_id": currentAssets[nextIndex].id.uuidString
            ]
        )
    }

    func updateDecision(for assetID: UUID, decision: Decision) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        assets[index].userDecision = decision
        scheduleManifestSave()
        traceEvent(
            "decision_updated",
            category: "culling",
            metadata: [
                "asset_id": assetID.uuidString,
                "decision": decision.rawValue
            ]
        )
    }

    func updateRating(for assetID: UUID, rating: Int?) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        assets[index].userRating = rating
        scheduleManifestSave()
        traceEvent(
            "rating_updated",
            category: "culling",
            metadata: [
                "asset_id": assetID.uuidString,
                "rating": rating.map(String.init) ?? "cleared"
            ]
        )
    }

    func markSelection(_ decision: Decision) {
        guard let selectedAssetID else { return }
        updateDecision(for: selectedAssetID, decision: decision)
        moveSelection(by: 1)
    }

    func clearSelectionDecision() {
        guard let selectedAssetID else { return }
        updateDecision(for: selectedAssetID, decision: .pending)
    }

    func rateSelection(_ rating: Int) {
        guard let selectedAssetID else { return }
        updateRating(for: selectedAssetID, rating: rating)
    }

    func clearSelectionRating() {
        guard let selectedAssetID else { return }
        updateRating(for: selectedAssetID, rating: nil)
    }

    /// 当前 Session 总进度：已决策 / 总数。
    var sessionDecisionProgress: (decided: Int, total: Int) {
        let total = assets.count
        let decided = assets.filter { $0.userDecision != .pending }.count
        return (decided, total)
    }

    func jumpToNextGroup() {
        guard !groups.isEmpty else { return }
        if let selectedGroupID,
           let currentIndex = groups.firstIndex(where: { $0.id == selectedGroupID }) {
            let nextIndex = (currentIndex + 1) % groups.count
            selectGroup(groups[nextIndex].id)
        } else {
            selectGroup(groups.first?.id)
        }
    }

    func jumpToPreviousGroup() {
        guard !groups.isEmpty else { return }
        if let selectedGroupID,
           let currentIndex = groups.firstIndex(where: { $0.id == selectedGroupID }) {
            let nextIndex = (currentIndex - 1 + groups.count) % groups.count
            selectGroup(groups[nextIndex].id)
        } else {
            selectGroup(groups.last?.id)
        }
    }

    /// 选片页左栏「All Photos」概览：`selectedGroupID = nil` 时右栏展示整个 session 的资产。
    func selectAllPhotosOverview() {
        selectGroup(nil)
    }

    /// 选片页右栏「Smart Group 全部图（Burst 折叠为单 cell）」。
    /// - 单图（subGroup.count == 1 / 不属于任何 subGroup）→ `.single`。
    /// - 多图 burst → `.burst`，UI 上以代表图 + 角标显示。
    var visibleSmartGroupCells: [SmartGroupCell] {
        let bursts = visibleBurstGroups
        if bursts.isEmpty {
            return visibleAssets.map { .single($0) }
        }
        return bursts.map { burst in
            burst.count == 1 ? .single(burst.assets[0]) : .burst(burst)
        }
    }

    /// 选中某个右栏 cell：单图直接选中，连拍组选中其代表图（中央会切到 burst 网格）。
    func selectSmartGroupCell(_ cell: SmartGroupCell) {
        switch cell {
        case .single(let asset):
            selectAsset(asset.id)
        case .burst(let burst):
            selectAsset(burst.coverAsset.id)
        }
    }

    func summary(for group: PhotoGroup?) -> GroupDecisionSummary {
        ensureDerivedState()

        if let group {
            return groupSummaryCache[group.id] ?? computeSummary(for: group.assets.compactMap { assetLookupCache[$0] })
        }

        return overallSummaryCache
    }

    func openExportPanel() {
        isExportPanelPresented = true
        traceEvent("export_panel_opened", category: "export")
    }

    func closeExportPanel() {
        isExportPanelPresented = false
        traceEvent("export_panel_closed", category: "export")
    }

    func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportOptions.outputPath = url
    }

    func chooseLightroomFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Lightroom Auto-Import Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportOptions.lrAutoImportFolder = url
    }

    func performExport() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard !isExporting else { return }
        guard !assets.isEmpty else {
            lastErrorMessage = "当前没有可导出的项目。"
            return
        }
        guard pickedAssetsCount > 0 else {
            lastErrorMessage = "请先至少标记一张 Picked 照片。"
            return
        }

        isExporting = true
        lastExportSummary = nil
        exportProgress = ExportProgress(phase: .preparing, completed: 0, total: 0, currentName: nil)

        // 写 Photos 路径：弹一次确认，给用户最后一次"我真的要写入照片库"的机会。
        if exportOptions.destination == .photosApp {
            let confirmed = await requestPhotosWriteConfirmation()
            if !confirmed {
                traceEvent("photos_write_cancelled_by_user", category: "export")
                isExporting = false
                exportProgress = nil
                return
            }
        }

        do {
            traceEvent(
                "export_started",
                category: "export",
                metadata: [
                    "destination": exportOptions.destination.rawValue,
                    "picked_count": String(pickedAssetsCount)
                ]
            )
            let adapter = try exportAdapter(for: exportOptions.destination)
            let isValid = try await adapter.validateConfiguration(options: exportOptions)
            guard isValid else {
                throw LumaError.configurationInvalid("导出配置不完整。")
            }

            // Photos 源 → Folder/Lightroom：导出阶段才按需把原图从 PhotoKit / iCloud 拉到 raw/。
            // Photos App 目标本身能复用 PHAsset，无需此步。
            let pickedAssets = assets.filter { asset in
                guard asset.userDecision == .picked else { return false }
                if let only = exportOptions.onlyAssetIDs { return only.contains(asset.id) }
                return true
            }
            if exportOptions.destination != .photosApp,
               let projectDirectory = currentProjectDirectory,
               pickedAssets.contains(where: { asset in
                   asset.rawURL == nil
                       && {
                           if case .photosLibrary(let id) = asset.source { return !id.isEmpty }
                           return false
                       }()
               }) {
                exportProgress = ExportProgress(phase: .fetchingOriginals, completed: 0, total: 0, currentName: nil)
                let rawDirectory = projectDirectory.appendingPathComponent("raw", isDirectory: true)
                let fetched = try await PhotosOriginalFetcher.fetchOriginals(
                    for: pickedAssets,
                    rawDirectory: rawDirectory,
                    progress: { [weak self] completed, total, name in
                        Task { @MainActor in
                            self?.exportProgress = ExportProgress(
                                phase: .fetchingOriginals,
                                completed: completed,
                                total: total,
                                currentName: name
                            )
                        }
                    }
                )
                if !fetched.isEmpty, let idx = activeSessionIndex {
                    for (assetID, url) in fetched {
                        if let assetIdx = sessions[idx].assets.firstIndex(where: { $0.id == assetID }) {
                            sessions[idx].assets[assetIdx].rawURL = url
                        }
                    }
                    sessions[idx].updatedAt = .now
                    invalidateDerivedState()
                }
            }

            exportProgress = ExportProgress(phase: .writing, completed: 0, total: pickedAssets.count, currentName: nil)
            let result = try await adapter.export(assets: assets, groups: groups, options: exportOptions)
            let archiveSummary = try await processRejectedAssetsAfterExport()
            saveExportSettings()
            isExportPanelPresented = false

            let archiveSuffix = archiveSummary.map { "；\($0)" } ?? ""
            lastExportSummary = "导出 \(result.exportedCount) 张到 \(result.destinationDescription)\(archiveSuffix)"
            lastSummaryStatus = lastExportSummary
            // 结构化结果：触发新版导出完成摘要 sheet（替代 alert）。
            lastExportResult = result

            if let idx = activeSessionIndex {
                let pickedIDs = assets.filter { $0.userDecision == .picked }.map(\.id)
                let hasFailures = !result.failures.isEmpty
                let job = ExportJob(
                    id: UUID(),
                    createdAt: Date(),
                    completedAt: .now,
                    status: hasFailures ? .failed : .completed,
                    options: exportOptions,
                    targetAssetIDs: pickedIDs,
                    exportedCount: result.exportedCount,
                    totalCount: max(pickedAssetsCount, 1),
                    speedBytesPerSecond: nil,
                    estimatedSecondsRemaining: nil,
                    destinationDescription: result.destinationDescription,
                    lastError: hasFailures ? "\(result.failures.count) 个文件失败" : nil,
                    cleanedCount: result.cleanedCount,
                    cleanupCancelledCount: result.cleanupCancelledCount,
                    albumDescription: result.albumDescription,
                    failures: result.failures
                )
                sessions[idx].exportJobs.append(job)
                sessions[idx].updatedAt = .now
                scheduleManifestSave()
            }
            traceMetric(
                "export_completed",
                category: "export",
                startedAt: startedAt,
                metadata: [
                    "destination": exportOptions.destination.rawValue,
                    "exported_count": String(result.exportedCount),
                    "failed_count": String(result.failedCount),
                    "cleaned_count": String(result.cleanedCount),
                    "cleanup_cancelled_count": String(result.cleanupCancelledCount),
                    "photos_cleanup_strategy": exportOptions.photosCleanupStrategy.rawValue,
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isExporting = false
        exportProgress = nil
        // 重试一次后清空 onlyAssetIDs，下次走全量导出。
        exportOptions.onlyAssetIDs = nil
    }

    /// 弹出 Photos 写入前的二次确认。挂起到用户在 sheet/alert 上点了「确认」或「取消」。
    @MainActor
    private func requestPhotosWriteConfirmation() async -> Bool {
        // 已在确认中：拒绝并发请求。
        if isAwaitingPhotosWriteConfirmation { return false }
        isAwaitingPhotosWriteConfirmation = true
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.pendingPhotosWriteContinuation = continuation
        }
    }

    /// 用户在写入前确认弹窗里点击「确认/取消」时由 UI 调用。
    func resolvePhotosWriteConfirmation(_ accepted: Bool) {
        guard isAwaitingPhotosWriteConfirmation else { return }
        isAwaitingPhotosWriteConfirmation = false
        let continuation = pendingPhotosWriteContinuation
        pendingPhotosWriteContinuation = nil
        continuation?.resume(returning: accepted)
    }

    /// 关闭导出完成摘要 sheet。
    func dismissExportResult() {
        lastExportResult = nil
        lastExportSummary = nil
    }

    /// 仅重试失败项：把上次失败的 assetID 写到 `onlyAssetIDs`，重新打开导出面板让用户复用上次配置。
    func retryFailedExports() {
        guard let result = lastExportResult, !result.failures.isEmpty else { return }
        exportOptions.onlyAssetIDs = Set(result.failures.map(\.assetID))
        lastExportResult = nil
        lastExportSummary = nil
        traceEvent(
            "export_retry_failed_only",
            category: "export",
            metadata: ["count": String(result.failures.count)]
        )
        isExportPanelPresented = true
    }

    /// 在访达里揭示上次导出的目标目录或路径。
    func revealLastExportDestination() {
        guard let result = lastExportResult else { return }
        if let url = result.destinationURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        traceEvent(
            "export_reveal_destination",
            category: "export",
            metadata: ["has_url": result.destinationURL != nil ? "1" : "0"]
        )
    }

    /// 跳转到系统照片 App。
    func openPhotosApp() {
        guard let url = URL(string: "photos://") else { return }
        NSWorkspace.shared.open(url)
        traceEvent("export_open_photos", category: "export")
    }

    private func runImportOperation(
        _ operation: @escaping (
            @escaping @Sendable (ImportProgress) -> Void,
            @escaping @Sendable (ImportedProjectSnapshot) -> Void
        ) async throws -> ImportedProject
    ) async {
        guard !isImporting else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastLoggedPhase: ImportPhase?

        isImporting = true
        importProgress = .init(phase: .scanning, completed: 0, total: 1, currentItemName: nil)
        lastErrorMessage = nil

        do {
            let imported = try await operation(
                { [weak self] progress in
                    Task { @MainActor in
                        self?.importProgress = progress
                        if lastLoggedPhase != progress.phase {
                            lastLoggedPhase = progress.phase
                            self?.traceEvent(
                                "import_phase_changed",
                                category: "import",
                                metadata: [
                                    "phase": progress.phase.rawValue,
                                    "completed": String(progress.completed),
                                    "total": String(progress.total)
                                ]
                            )
                        }
                    }
                },
                { [weak self] snapshot in
                    Task { @MainActor in
                        self?.apply(manifest: snapshot.manifest, in: snapshot.directory)
                    }
                }
            )

            apply(manifest: imported.manifest, in: imported.directory)
            recoverableImportSession = nil
            scheduleManifestSave()
            refreshProjectSummaries()
            triggerLocalScoringIfNeeded(force: true)
            importProgress = nil
            traceMetric(
                "import_completed",
                category: "import",
                startedAt: startedAt,
                metadata: [
                    "asset_count": String(imported.manifest.assets.count),
                    "group_count": String(imported.manifest.groups.count)
                ]
            )
        } catch {
            if let lumaError = error as? LumaError, case .userCancelled = lumaError {
                logger.log("Import cancelled.")
                traceEvent("import_cancelled", category: "import")
            } else {
                lastErrorMessage = error.localizedDescription
                if let session = importManager.mostRecentRecoverableSession() {
                    recoverableImportSession = session
                    importProgress = progress(for: session)
                    enqueueImportPrompt(.resumeSession(session))
                    traceEvent(
                        "import_paused_recoverable",
                        category: "import",
                        metadata: ["session_id": session.id.uuidString]
                    )
                } else {
                    importProgress = nil
                }
                traceError(
                    "import_operation_failed",
                    category: "import",
                    metadata: ["message": error.localizedDescription]
                )
            }
        }

        isImporting = false
        presentNextImportPromptIfPossible()
    }

    private func importDetectedSource(_ source: ImportSourceDescriptor) async {
        await runImportOperation { progress, snapshot in
            try await self.importManager.importFromSource(source, progress: progress, snapshot: snapshot)
        }
    }

    private func continueImport(_ session: ImportSession) async {
        await runImportOperation { progress, snapshot in
            try await self.importManager.resumeImport(session: session, progress: progress, snapshot: snapshot)
        }
    }

    private func startImportSourceMonitoring() {
        guard !isImportMonitoringStarted else { return }
        isImportMonitoringStarted = true

        importSourceMonitor.start { [weak self] source in
            Task { @MainActor in
                self?.handleDetectedImportSource(source)
            }
        }
        // 周期刷新 detectedImportSources，让"iPhone 已连接"等菜单状态可视化。
        Task { @MainActor [weak self] in
            while let self {
                self.detectedImportSources = await ImportSourceMonitor.detectSources()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// 是否检测到至少一台已解锁可读的 iPhone/iPad（USB 直连）。
    var hasConnectedIPhone: Bool {
        detectedImportSources.contains { source in
            if case .iPhone = source { return true }
            return false
        }
    }

    /// 是否检测到 SD 卡相关挂载。
    var hasConnectedSDCard: Bool {
        detectedImportSources.contains { source in
            if case .sdCard = source { return true }
            return false
        }
    }

    /// 已检测到的 iPhone 设备名（用于菜单二级标题）。
    var connectedIPhoneNames: [String] {
        detectedImportSources.compactMap { source in
            if case .iPhone(_, let name) = source { return name }
            return nil
        }
    }

    /// 已检测到的 SD 卡显示名。
    var connectedSDCardNames: [String] {
        detectedImportSources.compactMap { source in
            if case .sdCard(_, let name) = source { return name }
            return nil
        }
    }

    private func handleDetectedImportSource(_ source: ImportSourceDescriptor) {
        guard !isImporting else { return }
        traceEvent(
            "import_source_detected",
            category: "import",
            metadata: [
                "kind": source.traceKind,
                "stable_id": source.stableID,
                "display_name": source.displayName
            ]
        )

        if let recoverableImportSession, recoverableImportSession.source.stableID == source.stableID {
            enqueueImportPrompt(.resumeSession(recoverableImportSession))
            return
        }

        enqueueImportPrompt(.importSource(source))
    }

    private func enqueueImportPrompt(_ prompt: PendingImportPrompt) {
        if pendingImportPrompt == prompt || importPromptQueue.contains(prompt) {
            return
        }

        if pendingImportPrompt == nil && !isImporting {
            pendingImportPrompt = prompt
        } else {
            importPromptQueue.append(prompt)
        }
    }

    private func presentNextImportPromptIfPossible() {
        guard pendingImportPrompt == nil, !isImporting, !importPromptQueue.isEmpty else { return }
        pendingImportPrompt = importPromptQueue.removeFirst()
    }

    private func progress(for session: ImportSession) -> ImportProgress {
        switch session.phase {
        case .scanning:
            return .init(phase: .scanning, completed: 0, total: max(session.totalItems, 1), currentItemName: session.source.displayName)
        case .preparingThumbnails:
            return .init(phase: .preparingThumbnails, completed: session.completedThumbnails, total: max(session.totalItems, 1), currentItemName: session.source.displayName)
        case .copyingPreviews:
            return .init(phase: .copyingPreviews, completed: session.completedPreviews, total: max(session.totalItems, 1), currentItemName: session.source.displayName)
        case .copyingOriginals:
            return .init(phase: .copyingOriginals, completed: session.completedOriginals, total: max(session.totalItems, 1), currentItemName: session.source.displayName)
        case .paused:
            let completed = max(session.completedOriginals, session.completedPreviews, session.completedThumbnails)
            return .init(phase: .paused, completed: completed, total: max(session.totalItems, 1), currentItemName: session.lastError ?? session.source.displayName)
        case .finalizing:
            return .init(phase: .finalizing, completed: session.totalItems, total: max(session.totalItems, 1), currentItemName: session.source.displayName)
        }
    }

    private func apply(manifest: SessionManifest, in directory: URL) {
        currentProjectDirectory = directory
        currentManifestID = manifest.id
        var session = manifest.session
        if session.id != manifest.id {
            session = Session(
                id: manifest.id,
                name: session.name,
                createdAt: session.createdAt,
                updatedAt: .now,
                location: session.location,
                tags: session.tags,
                coverAssetID: session.coverAssetID,
                assets: session.assets,
                groups: session.groups,
                importSessions: session.importSessions,
                editingSessions: session.editingSessions,
                exportJobs: session.exportJobs
            )
        }
        session.assets = session.assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        session.updatedAt = .now
        sessions = [session]
        activeSessionID = session.id
        // sessions 直接赋值不会触发 assets/groups setter，必须手动 invalidate
        // 否则 ensureDerivedState 读到的还是上一次（或 bootstrap 时空）的 lookup cache，
        // 导致 selectedGroup/visibleAssets/visibleBurstGroups 全部失效。
        invalidateDerivedState()
        selectedGroupID = nil
        selectedAssetID = assets.first?.id
        localRejectedCount = assets.filter(\.isTechnicallyRejected).count
        cachePreparationTask?.cancel()
        ThumbnailCache.shared.invalidateAll()
        DisplayImageCache.shared.invalidateAll()
        scheduleRelevantCachePreparation()
        scheduleDeferredGroupNameRefreshIfNeeded()
    }

    private func persistManifestImmediatelyIfPossible() {
        guard let currentProjectDirectory, let i = activeSessionIndex else { return }
        manifestSaveTask?.cancel()
        sessions[i].updatedAt = .now
        let manifest = SessionManifest(id: currentManifestID, session: sessions[i])
        let manifestURL = AppDirectories.manifestURL(in: currentProjectDirectory)
        do {
            let data = try JSONEncoder.lumaEncoder.encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            logger.error("Failed to persist manifest before leaving project: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearCurrentProject() {
        currentProjectDirectory = nil
        currentManifestID = UUID()
        sessions = []
        activeSessionID = nil
        invalidateDerivedState()
        selectedGroupID = nil
        selectedAssetID = nil
        importProgress = nil
        isLocalScoring = false
        localScoringCompleted = 0
        localScoringTotal = 0
        localRejectedCount = 0
        cachePreparationTask?.cancel()
        groupNameRefreshTask?.cancel()
        ThumbnailCache.shared.invalidateAll()
        DisplayImageCache.shared.invalidateAll()
    }

    private func scheduleDeferredGroupNameRefreshIfNeeded() {
        guard !groups.isEmpty else { return }
        guard groups.contains(where: needsDeferredGroupNameRefresh) else { return }

        let snapshotGroups = groups
        groupNameRefreshTask?.cancel()
        groupNameRefreshTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            let refreshedGroups = await self.importManager.refreshGroupNames(for: snapshotGroups)
            guard !Task.isCancelled else { return }
            let existingIDs = Set(snapshotGroups.map(\.id))
            let refreshedIDs = Set(refreshedGroups.map(\.id))
            guard existingIDs == refreshedIDs else { return }
            let nameLookup = Dictionary(uniqueKeysWithValues: refreshedGroups.map { ($0.id, $0.name) })
            var updatedGroups = self.groups
            var changed = false
            for index in updatedGroups.indices {
                guard let name = nameLookup[updatedGroups[index].id], updatedGroups[index].name != name else { continue }
                updatedGroups[index].name = name
                changed = true
            }
            guard changed else { return }
            self.groups = updatedGroups
            self.scheduleManifestSave()
            self.traceMetric(
                "group_names_refreshed",
                category: "grouping",
                startedAt: startedAt,
                metadata: [
                    "group_count": String(refreshedGroups.count)
                ]
            )
        }
    }

    private func needsDeferredGroupNameRefresh(_ group: PhotoGroup) -> Bool {
        guard group.location != nil else { return false }
        let pattern = #"^\d{1,2}月\d{1,2}日·(上午|下午|夜晚)(·\d+)?$"#
        return group.name.range(of: pattern, options: .regularExpression) != nil
    }

    private func loadManifest(at directory: URL) throws -> SessionManifest {
        let data = try Data(contentsOf: AppDirectories.manifestURL(in: directory))
        let manifest = try JSONDecoder.lumaDecoder.decode(SessionManifest.self, from: data)

        // 防御：如果磁盘上的 manifest 版本比当前可识别版本更高（用户从更新版 Luma 回退），
        // 不强行加载，给一个友好的报错让用户去升级；不会因此把 manifest 写花。
        if manifest.schemaVersion > SessionManifest.currentSchemaVersion {
            throw LumaError.persistenceFailed(
                "项目 manifest 版本（v\(manifest.schemaVersion)）高于当前 Luma 可识别（v\(SessionManifest.currentSchemaVersion)）。请升级 Luma 后重试。"
            )
        }
        return manifest
    }

    /// 选片页同时显示「中央大图 + 右栏 Smart Group 缩略图网格」，所以预热策略=
    /// 1）保证当前选中张的大图就绪 + 邻图预取；2）右栏可见缩略图全部 trim/preheat。
    private func scheduleRelevantCachePreparation() {
        scheduleFocusedAssetCachePreparation()
        scheduleGridThumbnailWarmup()
    }

    private func scheduleGridThumbnailWarmup() {
        let assetsInScope = visibleAssets
        guard !assetsInScope.isEmpty else { return }

        cachePreparationTask?.cancel()
        cachePreparationTask = Task { @MainActor [assetsInScope] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            ThumbnailCache.shared.preheat(assets: Array(assetsInScope.prefix(24)))
            ThumbnailCache.shared.trim(toRetainAssetIDs: Set(assetsInScope.prefix(120).map(\.id)))
        }
    }

    private func scheduleFocusedAssetCachePreparation() {
        let assetsInScope = visibleAssets
        guard !assetsInScope.isEmpty else { return }

        guard let selectedAssetID else {
            scheduleGridThumbnailWarmup()
            return
        }

        cachePreparationTask?.cancel()
        cachePreparationTask = Task { @MainActor [assetsInScope, selectedAssetID] in
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            ThumbnailCache.shared.preheatNeighborhood(around: selectedAssetID, in: assetsInScope, radius: 10)
            DisplayImageCache.shared.preheatNeighborhood(around: selectedAssetID, in: assetsInScope, radius: 1)
        }
    }

    private func scheduleManifestSave() {
        guard let currentProjectDirectory else { return }
        manifestSaveTask?.cancel()

        guard let i = activeSessionIndex else { return }
        sessions[i].updatedAt = .now
        let manifest = SessionManifest(id: currentManifestID, session: sessions[i])
        let manifestURL = AppDirectories.manifestURL(in: currentProjectDirectory)

        manifestSaveTask = Task { [manifestURL, manifest] in
            try? await Task.sleep(for: .milliseconds(300))
            do {
                let data = try JSONEncoder.lumaEncoder.encode(manifest)
                try data.write(to: manifestURL, options: [.atomic])
            } catch {
                logger.error("Failed to save manifest: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func invalidateDerivedState() {
        derivedStateIsDirty = true
        invalidateSelectionDerivedState()
    }

    private func invalidateSelectionDerivedState() {
        visibleAssetsCacheGroupID = nil
        visibleAssetsCache = []
        visibleBurstGroupsCacheGroupID = nil
        visibleBurstGroupsCache = []
        selectedBurstContextCacheKey = nil
        selectedBurstContextCache = nil
    }

    private func ensureDerivedState() {
        guard derivedStateIsDirty else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime

        assetLookupCache = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        groupLookupCache = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        overallSummaryCache = computeSummary(for: assets)
        groupSummaryCache = groups.reduce(into: [:]) { cache, group in
            cache[group.id] = computeSummary(for: group.assets.compactMap { assetLookupCache[$0] })
        }
        derivedStateIsDirty = false
        traceMetric(
            "derived_state_rebuilt",
            category: "state",
            startedAt: startedAt,
            metadata: [
                "asset_lookup_count": String(assetLookupCache.count),
                "group_lookup_count": String(groupLookupCache.count),
                "group_summary_count": String(groupSummaryCache.count)
            ]
        )
    }

    private func computeSummary(for assets: [MediaAsset]) -> GroupDecisionSummary {
        var picked = 0
        var rejected = 0
        var recommended = 0

        for asset in assets {
            if asset.userDecision == .picked {
                picked += 1
            } else if asset.userDecision == .rejected || asset.isTechnicallyRejected {
                rejected += 1
            }

            if asset.aiScore?.recommended == true {
                recommended += 1
            }
        }

        let pending = max(0, assets.count - picked - rejected)

        return GroupDecisionSummary(
            total: assets.count,
            picked: picked,
            pending: pending,
            rejected: rejected,
            recommended: recommended
        )
    }

    private func triggerLocalScoringIfNeeded(force: Bool = false) {
        localScoringTask?.cancel()

        let candidates = assets.filter { asset in
            if force { return true }
            return asset.aiScore == nil
        }

        guard !candidates.isEmpty else {
            isLocalScoring = false
            localScoringCompleted = 0
            localScoringTotal = 0
            localRejectedCount = assets.filter(\.isTechnicallyRejected).count
            return
        }

        isLocalScoring = true
        localScoringCompleted = 0
        localScoringTotal = candidates.count
        localRejectedCount = assets.filter(\.isTechnicallyRejected).count

        localScoringTask = Task { [candidates, scorer = localMLScorer] in
            await withTaskGroup(of: (UUID, LocalMLAssessment).self) { group in
                var iterator = candidates.makeIterator()
                let parallelism = min(4, candidates.count)

                for _ in 0..<parallelism {
                    if let asset = iterator.next() {
                        group.addTask {
                            (asset.id, await scorer.score(asset: asset))
                        }
                    }
                }

                while let (assetID, assessment) = await group.next() {
                    await MainActor.run {
                        applyLocalAssessment(assessment, to: assetID)
                    }

                    if let nextAsset = iterator.next() {
                        group.addTask {
                            (nextAsset.id, await scorer.score(asset: nextAsset))
                        }
                    }
                }
            }

            await MainActor.run {
                isLocalScoring = false
                refreshGroupRecommendations()
                scheduleManifestSave()
            }
        }
    }

    private func applyLocalAssessment(_ assessment: LocalMLAssessment, to assetID: UUID) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        let wasTechnicallyRejected = assets[index].isTechnicallyRejected
        assets[index].issues = assessment.issues
        assets[index].aiScore = AIScore(
            // 真实算法是 Core Image + Vision 的本地启发式打分，并非 CoreML 模型；改名以避免误解。
            provider: "local-heuristic",
            scores: assessment.subscores,
            overall: assessment.score,
            comment: assessment.comment,
            recommended: assessment.recommended,
            timestamp: .now
        )

        localScoringCompleted += 1
        let isTechnicallyRejected = assets[index].isTechnicallyRejected
        if wasTechnicallyRejected != isTechnicallyRejected {
            localRejectedCount += isTechnicallyRejected ? 1 : -1
        }
    }

    private func refreshGroupRecommendations() {
        let assetLookup = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        for groupIndex in groups.indices {
            let groupAssets = groups[groupIndex].assets.compactMap { assetLookup[$0] }
            groups[groupIndex].recommendedAssets = groupAssets
                .filter { $0.aiScore?.recommended == true }
                .map(\.id)

            groups[groupIndex].subGroups = groups[groupIndex].subGroups.map { subGroup in
                let candidates = subGroup.assets
                    .compactMap { assetLookup[$0] }
                    .sorted { ($0.aiScore?.overall ?? 0) > ($1.aiScore?.overall ?? 0) }

                var updated = subGroup
                updated.bestAsset = candidates.first?.id
                return updated
            }
        }
    }

    /// SettingsView 直接调用：保存当前 exportOptions 的"默认值"部分（导出目录 / LR / 未选处理）。
    func saveDefaultsExplicitly() {
        saveExportSettings()
        traceEvent(
            "export_defaults_saved",
            category: "settings",
            metadata: [
                "rejected_handling": exportOptions.rejectedHandling.rawValue,
                "has_output_path": exportOptions.outputPath != nil ? "1" : "0",
                "has_lr_path": exportOptions.lrAutoImportFolder != nil ? "1" : "0"
            ]
        )
    }

    private func saveExportSettings() {
        do {
            let data = try JSONEncoder().encode(exportOptions)
            UserDefaults.standard.set(data, forKey: exportOptionsDefaultsKey)
        } catch {
            logger.error("Failed to save export settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadExportSettings() {
        if let data = UserDefaults.standard.data(forKey: exportOptionsDefaultsKey),
           let options = try? JSONDecoder().decode(ExportOptions.self, from: data) {
            exportOptions = options
        }
    }

    private func exportAdapter(for destination: ExportDestination) throws -> any ExportDestinationAdapter {
        switch destination {
        case .folder:
            return FolderExporter()
        case .lightroom:
            return LightroomExporter()
        case .photosApp:
            return PhotosAppExporter()
        }
    }

    private func processRejectedAssetsAfterExport() async throws -> String? {
        let archiveCandidates = assets.filter { $0.userDecision != .picked }
        guard !archiveCandidates.isEmpty else { return nil }

        switch exportOptions.rejectedHandling {
        case .discard:
            return "未选 \(archiveCandidates.count) 张未处理"
        case .archiveVideo:
            let batchName = "\(projectName)_\(ISO8601DateFormatter().string(from: .now))"
            let result = try await videoArchiver.archive(groups: groups, assets: archiveCandidates, batchName: batchName)
            return "生成 \(result.generatedFiles.count) 个归档视频到 \(result.outputDirectory.lastPathComponent)"
        case .shrinkKeep:
            let batchName = "\(projectName)_\(ISO8601DateFormatter().string(from: .now))"
            let result = try await videoArchiver.shrinkKeep(assets: archiveCandidates, batchName: batchName)
            return "缩小归档 \(result.generatedFiles.count) 张到 \(result.outputDirectory.lastPathComponent)"
        }
    }

    private func traceEvent(_ name: String, category: String, metadata: [String: String] = [:]) {
        RuntimeTrace.event(name, category: category, metadata: traceContext(metadata))
    }

    private func traceMetric(_ name: String, category: String, startedAt: TimeInterval, metadata: [String: String] = [:]) {
        var combined = metadata
        combined["duration_ms"] = Self.durationString(since: startedAt)
        RuntimeTrace.metric(name, category: category, metadata: traceContext(combined))
    }

    private func traceError(_ name: String, category: String, metadata: [String: String] = [:]) {
        RuntimeTrace.error(name, category: category, metadata: traceContext(metadata))
    }

    private func traceContext(_ metadata: [String: String]) -> [String: String] {
        let thumbnailSnapshot = ThumbnailCache.shared.snapshot()
        let displaySnapshot = DisplayImageCache.shared.snapshot()

        var context: [String: String] = [
            "project_name": projectName,
            "asset_count": String(assets.count),
            "group_count": String(groups.count),
            "visible_count": String(selectedGroup?.assets.count ?? assets.count),
            "selected_group_id": selectedGroupID?.uuidString ?? "all",
            "selected_asset_id": selectedAssetID?.uuidString ?? "none",
            "thumb_memory_items": String(thumbnailSnapshot.activeMemoryItems),
            "thumb_inflight": String(thumbnailSnapshot.inflightLoads),
            "display_memory_items": String(displaySnapshot.activeMemoryItems),
            "display_inflight": String(displaySnapshot.inflightLoads)
        ]

        if let currentProjectDirectory {
            context["project_directory"] = currentProjectDirectory.lastPathComponent
        }

        metadata.forEach { key, value in
            context[key] = value
        }

        return context
    }

    private static func durationString(since startedAt: TimeInterval) -> String {
        String(format: "%.2f", max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
    }

    private func urlsReferToSameLocation(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

struct GroupDecisionSummary {
    let total: Int
    let picked: Int
    let pending: Int
    let rejected: Int
    let recommended: Int

    var pickedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(picked) / Double(total)
    }

    var pendingFraction: Double {
        guard total > 0 else { return 0 }
        return Double(pending) / Double(total)
    }

    var rejectedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(rejected) / Double(total)
    }

    static let empty = GroupDecisionSummary(
        total: 0,
        picked: 0,
        pending: 0,
        rejected: 0,
        recommended: 0
    )
}

extension JSONDecoder {
    static var lumaDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension PendingImportPrompt {
    var kind: String {
        switch self {
        case .importSource:
            return "import_source"
        case .resumeSession:
            return "resume_session"
        }
    }
}

private extension ImportSourceDescriptor {
    var traceKind: String {
        switch self {
        case .folder:
            return "folder"
        case .sdCard:
            return "sd_card"
        case .iPhone:
            return "iphone"
        case .photosLibrary:
            return "photos_library"
        }
    }
}
