import AppKit
import Foundation
import Observation
import os

enum DisplayMode: String {
    case grid
    case single
}

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case imports
    case culling
    case editing
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return "图库"
        case .imports:
            return "导入"
        case .culling:
            return "筛选"
        case .editing:
            return "编辑"
        case .export:
            return "导出"
        }
    }

}

extension DisplayMode {
    var title: String {
        switch self {
        case .grid:
            return "网格"
        case .single:
            return "单页"
        }
    }
}

enum ExpeditionsGalleryLayout: String, CaseIterable, Sendable, Hashable {
    case grid
    case list
}

enum ProjectLibraryKind: Equatable, Sendable, Hashable {
    case management
    case allExpeditionsGallery(layout: ExpeditionsGalleryLayout)
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
    private let visionProviderFactory: @Sendable (ModelConfig) -> any VisionModelProvider
    private let batchSchedulerFactory: @Sendable () -> any BatchScheduling

    var currentProjectDirectory: URL?
    /// All expeditions known in-memory (typically the active project directory’s expedition).
    var expeditions: [Expedition] = []
    var activeExpeditionID: UUID?
    /// Stable identifier for the current project manifest.
    /// Set from the loaded manifest and reused on every save so the id never drifts.
    /// Exposed for UI snapshot tooling in the same module; set from manifest on load.
    var currentManifestID: UUID = UUID()
    var projectSummaries: [ProjectSummary] = []

    private var activeExpeditionIndex: Int? {
        guard let activeExpeditionID else { return nil }
        return expeditions.firstIndex { $0.id == activeExpeditionID }
    }

    var currentExpedition: Expedition? {
        guard let i = activeExpeditionIndex else { return nil }
        return expeditions[i]
    }

    var projectName: String {
        get { currentExpedition?.name ?? "Luma" }
        set {
            guard let i = activeExpeditionIndex else { return }
            expeditions[i].name = newValue
            expeditions[i].updatedAt = .now
        }
    }

    var createdAt: Date? {
        get { currentExpedition?.createdAt }
        set {
            guard let i = activeExpeditionIndex, let newValue else { return }
            expeditions[i].createdAt = newValue
            expeditions[i].updatedAt = .now
        }
    }

    var assets: [MediaAsset] {
        get { currentExpedition?.assets ?? [] }
        set {
            guard let i = activeExpeditionIndex else { return }
            expeditions[i].assets = newValue
            expeditions[i].updatedAt = .now
            invalidateDerivedState()
        }
    }

    var groups: [PhotoGroup] {
        get { currentExpedition?.groups ?? [] }
        set {
            guard let i = activeExpeditionIndex else { return }
            expeditions[i].groups = newValue
            expeditions[i].updatedAt = .now
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
    var recoverableImportSession: ImportSession?
    var importProgress: ImportProgress?
    var isImporting = false
    var displayMode: DisplayMode = .grid
    var currentSection: AppSection = .library
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
    var modelConfigs: [ModelConfig] = []
    var costTracker = CostTracker()
    var isLocalScoring = false
    var localScoringCompleted = 0
    var localScoringTotal = 0
    var localRejectedCount = 0
    var isCloudScoring = false
    var cloudScoringCompleted = 0
    var cloudScoringTotal = 0
    var cloudScoringStatus: String?
    var aiScoringStrategy: AIScoringStrategy = .budget
    var aiBudgetLimit: Double = 5.0
    var exportOptions: ExportOptions = .default
    var isProjectLibraryPresented = false
    var projectLibraryKind: ProjectLibraryKind = .management
    var isPerformanceDiagnosticsPresented = false
    var isExportPanelPresented = false
    var isExporting = false
    var lastExportSummary: String?

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
    private var selectedDisplayWarmupTask: Task<Void, Never>?
    private var groupNameRefreshTask: Task<Void, Never>?
    private let modelConfigsDefaultsKey = "Luma.modelConfigs"
    private let aiStrategyDefaultsKey = "Luma.aiScoringStrategy"
    private let aiBudgetDefaultsKey = "Luma.aiBudgetLimit"
    private let exportOptionsDefaultsKey = "Luma.exportOptions"

    init(
        enableImportMonitoring: Bool = true,
        visionProviderFactory: @escaping @Sendable (ModelConfig) -> any VisionModelProvider = VisionProviderFactory.makeProvider,
        batchSchedulerFactory: @escaping @Sendable () -> any BatchScheduling = { BatchScheduler() }
    ) {
        self.enableImportMonitoring = enableImportMonitoring
        self.visionProviderFactory = visionProviderFactory
        self.batchSchedulerFactory = batchSchedulerFactory
        loadAISettings()
        loadExportSettings()
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

    var expeditionImportSessions: [ImportSession] {
        currentExpedition?.importSessions ?? []
    }

    var importsHubSubtitle: String {
        guard let exp = currentExpedition else { return "尚未创建导入会话" }
        if let last = exp.importSessions.last {
            return "\(exp.name) · \(last.source.displayName)"
        }
        return "\(exp.name) · 尚未有导入记录"
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
        if isLocalScoring || isCloudScoring {
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

        guard let selectedGroup else { return [] }

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

    var cloudScoringFraction: Double {
        guard cloudScoringTotal > 0 else { return 0 }
        return Double(cloudScoringCompleted) / Double(cloudScoringTotal)
    }

    var activePrimaryModel: ModelConfig? {
        modelConfigs.first { $0.isActive && $0.role == .primary }
    }

    var activePremiumModel: ModelConfig? {
        modelConfigs.first { $0.isActive && $0.role == .premiumFallback }
    }

    var pickedAssetsCount: Int {
        assets.filter { $0.userDecision == .picked }.count
    }

    var archiveCandidatesCount: Int {
        assets.filter { $0.userDecision != .picked }.count
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
            let manifest = try JSONDecoder.lumaDecoder.decode(ExpeditionManifest.self, from: data)
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

    func openProjectLibrary() {
        projectLibraryKind = .management
        refreshProjectSummaries()
        isProjectLibraryPresented = true
    }

    /// Full-screen gallery from Library hub (Stitch: “Luma - All Expeditions Gallery”).
    func openAllExpeditionsGallery(layout: ExpeditionsGalleryLayout) {
        projectLibraryKind = .allExpeditionsGallery(layout: layout)
        refreshProjectSummaries()
        isProjectLibraryPresented = true
    }

    func closeProjectLibrary() {
        isProjectLibraryPresented = false
        projectLibraryKind = .management
    }

    func openPerformanceDiagnostics() {
        isPerformanceDiagnosticsPresented = true
        traceEvent("performance_diagnostics_opened", category: "diagnostics")
    }

    func closePerformanceDiagnostics() {
        isPerformanceDiagnosticsPresented = false
        traceEvent("performance_diagnostics_closed", category: "diagnostics")
    }

    func openProject(_ summary: ProjectSummary) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let manifest = try loadManifest(at: summary.directory)
            apply(manifest: manifest, in: summary.directory)
            refreshProjectSummaries()
            triggerLocalScoringIfNeeded()
            isProjectLibraryPresented = false
            projectLibraryKind = .management
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
            projectSummaries = directories.map { directory in
                do {
                    let manifest = try loadManifest(at: directory)
                    return ProjectSummary(
                        id: directory,
                        directory: directory,
                        name: manifest.name,
                        createdAt: manifest.createdAt,
                        state: .ready(assetCount: manifest.assets.count, groupCount: manifest.groups.count),
                        isCurrent: urlsReferToSameLocation(directory, currentProjectDirectory)
                    )
                } catch {
                    let values = try? directory.resourceValues(forKeys: [.creationDateKey])
                    return ProjectSummary(
                        id: directory,
                        directory: directory,
                        name: directory.lastPathComponent,
                        createdAt: values?.creationDate ?? .distantPast,
                        state: .unavailable(reason: error.localizedDescription),
                        isCurrent: urlsReferToSameLocation(directory, currentProjectDirectory)
                    )
                }
            }
        } catch {
            projectSummaries = []
            lastErrorMessage = error.localizedDescription
        }
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

    func selectGroup(_ groupID: UUID?) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        selectedDisplayWarmupTask?.cancel()
        selectedGroupID = groupID
        if let first = visibleAssets.first {
            selectedAssetID = first.id
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
        if displayMode == .single {
            selectedDisplayWarmupTask?.cancel()
            scheduleFocusedAssetCachePreparation()
        } else {
            scheduleSelectedAssetDisplayWarmup(for: assetID)
        }
        traceMetric(
            "asset_selected",
            category: "interaction",
            startedAt: startedAt,
            metadata: [
                "asset_id": assetID.uuidString,
                "mode": displayMode.rawValue
            ]
        )
    }

    func setDisplayMode(_ mode: DisplayMode) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard mode == .grid || !visibleAssets.isEmpty else { return }
        if mode == .single, selectedAsset == nil {
            selectedAssetID = visibleAssets.first?.id
        }
        if mode == .single {
            selectedDisplayWarmupTask?.cancel()
        }
        displayMode = mode
        scheduleRelevantCachePreparation()
        traceMetric(
            "display_mode_changed",
            category: "interaction",
            startedAt: startedAt,
            metadata: ["display_mode": mode.rawValue]
        )
    }

    func toggleDisplayMode() {
        let nextMode: DisplayMode = displayMode == .grid ? .single : .grid
        setDisplayMode(nextMode)
    }

    func moveSelection(by delta: Int) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let currentAssets = visibleAssets
        guard !currentAssets.isEmpty else { return }

        let currentIndex = currentAssets.firstIndex(where: { $0.id == selectedAssetID }) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), currentAssets.count - 1)
        selectedAssetID = currentAssets[nextIndex].id
        if displayMode == .single {
            scheduleFocusedAssetCachePreparation()
        }
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

    func selectRecommendedInCurrentScope() {
        let targetAssets = selectedGroup.map { group in
            assets.filter { group.assets.contains($0.id) }
        } ?? assets

        let recommended = targetAssets.filter { $0.aiScore?.recommended == true }
        for asset in recommended {
            updateDecision(for: asset.id, decision: .picked)
        }
        traceEvent(
            "recommended_assets_selected",
            category: "culling",
            metadata: ["count": String(recommended.count)]
        )
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

    func summary(for group: PhotoGroup?) -> GroupDecisionSummary {
        ensureDerivedState()

        if let group {
            return groupSummaryCache[group.id] ?? computeSummary(for: group.assets.compactMap { assetLookupCache[$0] })
        }

        return overallSummaryCache
    }

    func saveAISettings() {
        do {
            let data = try JSONEncoder().encode(modelConfigs)
            UserDefaults.standard.set(data, forKey: modelConfigsDefaultsKey)
            UserDefaults.standard.set(aiScoringStrategy.rawValue, forKey: aiStrategyDefaultsKey)
            UserDefaults.standard.set(aiBudgetLimit, forKey: aiBudgetDefaultsKey)
        } catch {
            logger.error("Failed to save AI settings: \(error.localizedDescription, privacy: .public)")
        }
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

            let result = try await adapter.export(assets: assets, groups: groups, options: exportOptions)
            let archiveSummary = try await processRejectedAssetsAfterExport()
            saveExportSettings()
            isExportPanelPresented = false

            let archiveSuffix = archiveSummary.map { "；\($0)" } ?? ""
            lastExportSummary = "导出 \(result.exportedCount) 张到 \(result.destinationDescription)\(archiveSuffix)"
            cloudScoringStatus = lastExportSummary

            if let idx = activeExpeditionIndex {
                let pickedIDs = assets.filter { $0.userDecision == .picked }.map(\.id)
                let job = ExportJob(
                    id: UUID(),
                    createdAt: Date(),
                    completedAt: .now,
                    status: .completed,
                    options: exportOptions,
                    targetAssetIDs: pickedIDs,
                    exportedCount: result.exportedCount,
                    totalCount: max(pickedAssetsCount, 1),
                    speedBytesPerSecond: nil,
                    estimatedSecondsRemaining: nil,
                    destinationDescription: result.destinationDescription,
                    lastError: nil
                )
                expeditions[idx].exportJobs.append(job)
                expeditions[idx].updatedAt = .now
            }
            traceMetric(
                "export_completed",
                category: "export",
                startedAt: startedAt,
                metadata: [
                    "destination": exportOptions.destination.rawValue,
                    "exported_count": String(result.exportedCount)
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isExporting = false
    }

    func saveModel(
        id: UUID?,
        name: String,
        apiProtocol: APIProtocol,
        endpoint: String,
        modelId: String,
        apiKey: String,
        isActive: Bool,
        role: ModelRole,
        maxConcurrency: Int,
        costPerInputToken: Double?,
        costPerOutputToken: Double?
    ) {
        let modelID = id ?? UUID()
        let account = "model-\(modelID.uuidString)"

        if !apiKey.isEmpty {
            do {
                try KeychainHelper.save(apiKey, service: "Luma.AIModel", account: account)
            } catch {
                lastErrorMessage = error.localizedDescription
                return
            }
        }

        let config = ModelConfig(
            id: modelID,
            name: name,
            apiProtocol: apiProtocol,
            endpoint: endpoint,
            apiKeyReference: account,
            modelId: modelId,
            isActive: isActive,
            role: role,
            maxConcurrency: max(1, maxConcurrency),
            costPerInputToken: costPerInputToken,
            costPerOutputToken: costPerOutputToken,
            calibrationOffset: 0
        )

        if let index = modelConfigs.firstIndex(where: { $0.id == modelID }) {
            modelConfigs[index] = config
        } else {
            modelConfigs.append(config)
        }

        modelConfigs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAISettings()
    }

    func deleteModel(_ modelID: UUID) {
        guard let model = modelConfigs.first(where: { $0.id == modelID }) else { return }
        KeychainHelper.delete(service: "Luma.AIModel", account: model.keychainAccount)
        modelConfigs.removeAll { $0.id == modelID }
        saveAISettings()
    }

    func testModelConnection(_ modelID: UUID) async {
        guard let model = modelConfigs.first(where: { $0.id == modelID }) else { return }
        cloudScoringStatus = "正在测试 \(model.name)..."

        do {
            let provider = visionProviderFactory(model)
            _ = try await provider.testConnection()
            cloudScoringStatus = "\(model.name) 连接成功"
        } catch {
            cloudScoringStatus = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func startCloudScoring() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard !isCloudScoring else { return }
        guard !assets.isEmpty else {
            lastErrorMessage = "当前没有可评分的项目。"
            return
        }
        guard let primaryModel = activePrimaryModel else {
            lastErrorMessage = "请先在设置中配置并启用一个 Primary AI 模型。"
            return
        }

        let primaryProvider = visionProviderFactory(primaryModel)
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let groupsSnapshot = groups
        let premiumModel = activePremiumModel
        let scheduler = batchSchedulerFactory()

        isCloudScoring = true
        cloudScoringCompleted = 0
        cloudScoringTotal = max(1, groups.count)
        cloudScoringStatus = "准备按组评分..."
        costTracker.reset()
        traceEvent(
            "cloud_scoring_started",
            category: "ai",
            metadata: [
                "group_count": String(groups.count),
                "strategy": aiScoringStrategy.rawValue,
                "primary_model": primaryModel.name
            ]
        )

        do {
            let groupResult = try await scheduler.scoreGroups(
                groupsSnapshot,
                assetsByID: assetsByID,
                provider: primaryProvider,
                modelConfig: primaryModel
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.cloudScoringCompleted = progress.completedGroups
                    self?.cloudScoringTotal = progress.totalGroups
                    self?.cloudScoringStatus = "AI 评分中：\(progress.currentGroupName)"
                }
            }

            applyGroupScores(groupResult)

            let detailProviderConfig: ModelConfig?
            switch aiScoringStrategy {
            case .budget:
                detailProviderConfig = nil
            case .balanced, .bestQuality:
                detailProviderConfig = premiumModel ?? primaryModel
            }

            if let detailProviderConfig {
                let detailProvider = visionProviderFactory(detailProviderConfig)
                let detailCandidates = detailCandidateIDs()
                let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
                let detailResult = try await scheduler.analyzeDetails(
                    assetIDs: detailCandidates,
                    assetsByID: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }),
                    groupsByID: groupsByID,
                    provider: detailProvider,
                    modelConfig: detailProviderConfig
                )
                applyDetailedSuggestions(detailResult.0)
                detailResult.1.forEach { costTracker.record($0) }
            }

            if costTracker.totalCost > aiBudgetLimit {
                lastErrorMessage = String(format: "AI 评分已超过预算阈值 $%.2f", aiBudgetLimit)
            }

            traceMetric(
                "cloud_scoring_completed",
                category: "ai",
                startedAt: startedAt,
                metadata: [
                    "group_count": String(groups.count),
                    "total_cost": String(format: "%.4f", costTracker.totalCost)
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isCloudScoring = false
        cloudScoringStatus = nil
        scheduleManifestSave()
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

    private func apply(manifest: ExpeditionManifest, in directory: URL) {
        currentProjectDirectory = directory
        currentManifestID = manifest.id
        var expedition = manifest.expedition
        if expedition.id != manifest.id {
            expedition = Expedition(
                id: manifest.id,
                name: expedition.name,
                createdAt: expedition.createdAt,
                updatedAt: .now,
                location: expedition.location,
                tags: expedition.tags,
                coverAssetID: expedition.coverAssetID,
                assets: expedition.assets,
                groups: expedition.groups,
                importSessions: expedition.importSessions,
                editingSessions: expedition.editingSessions,
                exportJobs: expedition.exportJobs
            )
        }
        expedition.assets = expedition.assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        expedition.updatedAt = .now
        expeditions = [expedition]
        activeExpeditionID = expedition.id
        selectedGroupID = nil
        selectedAssetID = assets.first?.id
        displayMode = .grid
        localRejectedCount = assets.filter(\.isTechnicallyRejected).count
        cachePreparationTask?.cancel()
        ThumbnailCache.shared.invalidateAll()
        DisplayImageCache.shared.invalidateAll()
        scheduleRelevantCachePreparation()
        scheduleDeferredGroupNameRefreshIfNeeded()
    }

    private func clearCurrentProject() {
        currentProjectDirectory = nil
        currentManifestID = UUID()
        expeditions = []
        activeExpeditionID = nil
        selectedGroupID = nil
        selectedAssetID = nil
        displayMode = .grid
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

    private func loadManifest(at directory: URL) throws -> ExpeditionManifest {
        let data = try Data(contentsOf: AppDirectories.manifestURL(in: directory))
        return try JSONDecoder.lumaDecoder.decode(ExpeditionManifest.self, from: data)
    }

    private func scheduleRelevantCachePreparation() {
        if displayMode == .single {
            scheduleFocusedAssetCachePreparation()
        } else {
            scheduleGridThumbnailWarmup()
        }
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

    private func scheduleSelectedAssetDisplayWarmup(for assetID: UUID) {
        selectedDisplayWarmupTask?.cancel()
        selectedDisplayWarmupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self, !Task.isCancelled, self.displayMode == .grid, self.selectedAssetID == assetID else { return }
            guard let asset = self.assetLookupCache[assetID] else { return }
            DisplayImageCache.shared.preheat(assets: [asset])
        }
    }

    private func scheduleManifestSave() {
        guard let currentProjectDirectory else { return }
        manifestSaveTask?.cancel()

        guard let i = activeExpeditionIndex else { return }
        expeditions[i].updatedAt = .now
        let manifest = ExpeditionManifest(id: currentManifestID, expedition: expeditions[i])
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
            provider: "local-coreml",
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

    private func loadAISettings() {
        if let data = UserDefaults.standard.data(forKey: modelConfigsDefaultsKey),
           let configs = try? JSONDecoder().decode([ModelConfig].self, from: data) {
            modelConfigs = configs
        }

        if let rawValue = UserDefaults.standard.string(forKey: aiStrategyDefaultsKey),
           let strategy = AIScoringStrategy(rawValue: rawValue) {
            aiScoringStrategy = strategy
        }

        let budget = UserDefaults.standard.double(forKey: aiBudgetDefaultsKey)
        if budget > 0 {
            aiBudgetLimit = budget
        }
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

    private func applyGroupScores(_ result: BatchSchedulerResult) {
        for (assetID, score) in result.scoresByAssetID {
            guard let index = assets.firstIndex(where: { $0.id == assetID }) else { continue }
            assets[index].aiScore = score
        }

        for (groupID, comment) in result.groupCommentsByID {
            guard let index = groups.firstIndex(where: { $0.id == groupID }) else { continue }
            groups[index].groupComment = comment.isEmpty ? nil : comment
        }

        for (groupID, recommendedAssets) in result.recommendedByGroupID {
            guard let index = groups.firstIndex(where: { $0.id == groupID }) else { continue }
            groups[index].recommendedAssets = recommendedAssets
        }

        result.costRecords.forEach { costTracker.record($0) }
        refreshGroupRecommendations()
    }

    private func detailCandidateIDs() -> [UUID] {
        let scoredAssets = assets
            .filter { !$0.isTechnicallyRejected && $0.aiScore != nil }
            .sorted { ($0.aiScore?.overall ?? 0) > ($1.aiScore?.overall ?? 0) }

        switch aiScoringStrategy {
        case .budget:
            return []
        case .balanced:
            let count = max(1, Int(ceil(Double(scoredAssets.count) * 0.2)))
            return Array(scoredAssets.prefix(count)).map(\.id)
        case .bestQuality:
            return scoredAssets.map(\.id)
        }
    }

    private func applyDetailedSuggestions(_ suggestions: [UUID: EditSuggestions]) {
        for (assetID, editSuggestions) in suggestions {
            guard let index = assets.firstIndex(where: { $0.id == assetID }) else { continue }
            assets[index].editSuggestions = editSuggestions
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
            "display_mode": displayMode.rawValue,
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
        }
    }
}
