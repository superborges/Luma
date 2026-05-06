import AppKit
import Foundation
import GRDB
import Observation
import os

enum NavigationItem: Hashable, Sendable {
    case allPhotos
    case macPhotos
    case recentlyAdded
    case unorganized
    case expedition(UUID)
    case album(UUID)
    case smartAlbum(SmartAlbumFilter)
    case taskList
}

@MainActor @Observable
final class LibraryStore {

    // MARK: - Dependencies

    let db: LumaDatabase
    let assetManager: AssetManager
    let expeditionManager: ExpeditionManager
    let assetSourceManager: AssetSourceManager
    let photoGroupRepo: any PhotoGroupRepository
    let scoreRepo: any AssetScoreRepository
    let assetRepo: any MasterAssetRepository
    let expeditionAssetRepo: any ExpeditionAssetRepository
    let importSessionRepo: any ImportSessionRepository

    private static let logger = Logger(subsystem: "Luma", category: "LibraryStore")

    // MARK: - Navigation State

    var selectedNavItem: NavigationItem? = nil

    // MARK: - Data

    private(set) var expeditions: [Expedition] = []
    private(set) var allAssetsCount: Int = 0
    private(set) var allAssets: [MasterAsset] = []
    private(set) var recentlyAddedAssets: [MasterAsset] = []
    private(set) var unorganizedAssets: [MasterAsset] = []
    private(set) var expeditionAssetCounts: [UUID: Int] = [:]
    private(set) var expeditionGroupCounts: [UUID: Int] = [:]
    private(set) var invalidReferenceCounts: [UUID: Int] = [:]

    // MARK: - Album Data

    private(set) var albums: [LumaAlbum] = []
    private(set) var albumAssetCounts: [UUID: Int] = [:]
    private(set) var albumSyncStatuses: [UUID: AlbumSyncStatus] = [:]
    private var albumManager: AlbumManager?
    private let albumSyncAdapter: any AlbumSyncAdapter = PhotosAlbumSyncAdapter()

    // MARK: - Action Data

    private(set) var activeActionJobs: [ActionJob] = []
    private(set) var completedActionJobs: [ActionJob] = []
    private var actionRunner: ActionRunner?

    // MARK: - Task State

    var isImporting: Bool = false
    var importProgress: ImportProgress?
    var importError: String?

    // MARK: - Mac Photos State

    private(set) var macPhotosManager: MacPhotosManager?
    var macPhotosConnected: Bool { macPhotosManager?.isConnected ?? false }
    var macPhotosIndexProgress: MacPhotosIndexProgress? { macPhotosManager?.indexProgress }
    var macPhotosTotalCount: Int { macPhotosManager?.totalIndexedCount ?? 0 }
    var macPhotosLastSync: Date? { macPhotosManager?.lastSyncDate }
    var macPhotosIsIndexing: Bool { macPhotosManager?.isIndexing ?? false }
    var macPhotosAuthStatus: PhotoAuthorizationStatus { macPhotosManager?.authorizationStatus ?? .notDetermined }

    // MARK: - Workspace

    private(set) var workspaceStore: ExpeditionWorkspaceStore?

    // MARK: - Init

    init(
        db: LumaDatabase,
        assetManager: AssetManager,
        expeditionManager: ExpeditionManager,
        assetSourceManager: AssetSourceManager,
        photoGroupRepo: any PhotoGroupRepository,
        scoreRepo: any AssetScoreRepository,
        assetRepo: any MasterAssetRepository,
        expeditionAssetRepo: any ExpeditionAssetRepository,
        importSessionRepo: any ImportSessionRepository
    ) {
        self.db = db
        self.assetManager = assetManager
        self.expeditionManager = expeditionManager
        self.assetSourceManager = assetSourceManager
        self.photoGroupRepo = photoGroupRepo
        self.scoreRepo = scoreRepo
        self.assetRepo = assetRepo
        self.expeditionAssetRepo = expeditionAssetRepo
        self.importSessionRepo = importSessionRepo

        self.macPhotosManager = MacPhotosManager(
            provider: SystemPhotoLibraryProvider(),
            assetManager: assetManager,
            assetSourceManager: assetSourceManager,
            db: db
        )
        self.albumManager = AlbumManager(
            db: db,
            albumRepo: GRDBAlbumRepository(dbQueue: db.dbQueue)
        )
        let runner = ActionRunner(
            db: db,
            actionJobRepo: GRDBActionJobRepository(dbQueue: db.dbQueue),
            archiveManifestRepo: GRDBArchiveManifestRepository(dbQueue: db.dbQueue),
            expeditionAssetRepo: expeditionAssetRepo,
            assetRepo: assetRepo
        )
        runner.albumManager = self.albumManager
        runner.albumSyncAdapter = self.albumSyncAdapter
        runner.photoGroupRepo = photoGroupRepo
        runner.scoreRepo = scoreRepo
        self.actionRunner = runner
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        if let mgr = macPhotosManager, mgr.isConnected {
            refreshMacPhotosState()
        }
        refreshExpeditions()
        refreshCounts()
        refreshInvalidReferenceCounts()
        refreshAlbums()
        refreshActionJobs()
        await validatePhotosAlbumRefs()
    }

    // MARK: - Albums

    func refreshAlbums() {
        guard let mgr = albumManager else { return }
        do {
            albums = try mgr.fetchAllAlbums()
            var counts: [UUID: Int] = [:]
            for album in albums {
                counts[album.id] = (try? mgr.fetchAssetCount(albumId: album.id)) ?? 0
                if album.kind == .photosBacked, albumSyncStatuses[album.id] == nil {
                    albumSyncStatuses[album.id] = .synced
                }
            }
            albumAssetCounts = counts
        } catch {
            Self.logger.error("Failed to refresh albums: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createManualAlbum(name: String, expeditionId: UUID? = nil) throws -> LumaAlbum {
        guard let mgr = albumManager else { throw LumaError.persistenceFailed("AlbumManager not available") }
        let album = try mgr.createManualAlbum(name: name, expeditionId: expeditionId)
        refreshAlbums()
        return album
    }

    func deleteAlbum(id: UUID) throws {
        guard let mgr = albumManager else { return }
        try mgr.deleteAlbum(id: id)
        refreshAlbums()
    }

    func addAssetsToAlbum(albumId: UUID, assetIds: [UUID]) throws {
        guard let mgr = albumManager else { return }
        try mgr.addAssets(albumId: albumId, assetIds: assetIds)
        refreshAlbums()
    }

    func removeAssetsFromAlbum(albumId: UUID, assetIds: [UUID]) throws {
        guard let mgr = albumManager else { return }
        try mgr.removeAssets(albumId: albumId, assetIds: assetIds)
        refreshAlbums()
    }

    func fetchAlbumAssets(albumId: UUID) throws -> [MasterAsset] {
        guard let mgr = albumManager else { return [] }
        let assetIds = try mgr.fetchAlbumAssetIds(albumId: albumId)
        let records = try assetRepo.fetchByIds(assetIds.map(\.uuidString))
        let lookup = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return assetIds.compactMap { id in
            lookup[id.uuidString].flatMap { MasterAsset(record: $0) }
        }
    }

    func fetchAssetsByIds(_ ids: [UUID]) throws -> [MasterAsset] {
        let records = try assetRepo.fetchByIds(ids.map(\.uuidString))
        let lookup = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { id in
            lookup[id.uuidString].flatMap { MasterAsset(record: $0) }
        }
    }

    func fetchAlbum(id: UUID) throws -> LumaAlbum? {
        guard let mgr = albumManager else { return nil }
        return try mgr.fetchAlbum(id: id)
    }

    func evaluateSmartAlbum(filter: SmartAlbumFilter, expeditionId: UUID? = nil) throws -> [UUID] {
        guard let mgr = albumManager else { return [] }
        let rule = SmartAlbumRule(
            scope: expeditionId.map { .expedition($0) } ?? .library,
            filters: [filter]
        )
        return try mgr.evaluateSmartRule(rule, expeditionId: expeditionId)
    }

    // MARK: - Action Jobs

    func refreshActionJobs() {
        guard let runner = actionRunner else { return }
        do {
            activeActionJobs = try runner.fetchActiveJobs()
            completedActionJobs = try runner.fetchCompletedJobs()
        } catch {
            Self.logger.error("Failed to refresh action jobs: \(error.localizedDescription)")
        }
    }

    // MARK: - Action Execution

    var isActionPanelPresented = false
    private(set) var lastActionResult: ExportResult?
    var isActionRunning: Bool { actionRunner?.isRunning ?? false }
    var currentActionProgress: ArchiveProgress? { actionRunner?.progress }
    var currentActionJobKind: ActionKind? { actionRunner?.currentJob?.kind }

    func submitAndRunAction(
        kind: ActionKind,
        expeditionId: UUID? = nil,
        albumId: UUID? = nil,
        targetAssetIds: [UUID] = [],
        exportOptions: ExportOptions? = nil
    ) async throws {
        guard let runner = actionRunner else {
            throw LumaError.persistenceFailed("ActionRunner not available")
        }
        if let opts = exportOptions {
            runner.exportOptions = opts
        }
        let job = try runner.submit(
            kind: kind,
            expeditionId: expeditionId,
            albumId: albumId,
            targetAssetIds: targetAssetIds
        )
        refreshActionJobs()
        try await runner.run(job: job)
        lastActionResult = runner.lastExportResult
        refreshActionJobs()
    }

    func dismissActionResult() {
        lastActionResult = nil
    }

    func revealInFinder(url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    // MARK: - Album Sync

    func syncAlbumToPhotos(albumId: UUID) async throws {
        guard let mgr = albumManager else {
            throw LumaError.persistenceFailed("AlbumManager not available")
        }

        albumSyncStatuses[albumId] = .syncing

        do {
            let assets = try fetchAlbumAssets(albumId: albumId)
            let existingRef = try mgr.fetchExternalRef(albumId: albumId)

            if let ref = existingRef {
                try await albumSyncAdapter.updateAlbum(ref, assets: assets)
            } else {
                guard let album = try mgr.fetchAlbum(id: albumId) else {
                    throw LumaError.persistenceFailed("Album not found")
                }
                var ref = try await albumSyncAdapter.createAlbum(name: album.name, assets: assets)
                ref.albumId = albumId
                try mgr.markAlbumAsSynced(albumId: albumId, ref: ref)
            }

            albumSyncStatuses[albumId] = .synced
            refreshAlbums()
        } catch {
            albumSyncStatuses[albumId] = hasExistingRef(albumId: albumId) ? .stale : .notSynced
            throw error
        }
    }

    private func hasExistingRef(albumId: UUID) -> Bool {
        guard let mgr = albumManager,
              let _ = try? mgr.fetchExternalRef(albumId: albumId) else { return false }
        return true
    }

    func validatePhotosAlbumRefs() async {
        guard let mgr = albumManager else { return }
        for album in albums where album.kind == .photosBacked {
            do {
                let isValid = try await mgr.validateAlbumRef(albumId: album.id, adapter: albumSyncAdapter)
                albumSyncStatuses[album.id] = isValid ? .synced : .stale
            } catch {
                albumSyncStatuses[album.id] = .stale
            }
        }
    }

    func convertAlbumToLocal(albumId: UUID) throws {
        guard let mgr = albumManager else { return }
        try mgr.convertToLocalAlbum(albumId: albumId)
        albumSyncStatuses[albumId] = .notSynced
        refreshAlbums()
    }

    func rebindAlbumToPhotos(albumId: UUID) async throws {
        guard let mgr = albumManager else {
            throw LumaError.persistenceFailed("AlbumManager not available")
        }
        try mgr.deleteExternalRef(albumId: albumId)
        try mgr.convertToLocalAlbum(albumId: albumId)
        try await syncAlbumToPhotos(albumId: albumId)
    }

    // MARK: - Mac Photos

    func connectMacPhotos() async throws {
        guard let mgr = macPhotosManager else { return }
        try await mgr.connect()
        try ensureMacPhotosExpedition()
        refreshExpeditions()
        refreshCounts()
        refreshMacPhotosAssets()
    }

    func disconnectMacPhotos() {
        macPhotosManager?.disconnect()
        refreshExpeditions()
    }

    func refreshMacPhotosIndex() async {
        await macPhotosManager?.refreshIndex()
        refreshCounts()
        refreshMacPhotosAssets()
    }

    private func refreshMacPhotosState() {
        guard let mgr = macPhotosManager else { return }
        if let source = try? assetSourceManager.fetchByKind(.macPhotos), source.kind == .macPhotos {
            let count = (try? db.dbQueue.read { db in
                try MasterAssetRecord
                    .filter(Column("sourceKind") == AssetSourceKind.macPhotos.rawValue)
                    .fetchCount(db)
            }) ?? 0
            if count > 0 {
                mgr.restoreIndexedCount(count)
            }
        }
    }

    private func ensureMacPhotosExpedition() throws {
        let existing = try expeditionManager.listExpeditions().first(where: { $0.isMacPhotos })
        if existing == nil {
            _ = try expeditionManager.createExpedition(
                name: "Mac Photos",
                subtitle: "系统照片图库",
                sourceMode: .macPhotos,
                status: .reviewing,
                startDate: nil,
                endDate: nil,
                coverAssetId: nil,
                createdAt: Date(),
                isMacPhotos: true
            )
        }
    }

    // MARK: - Expedition Management

    func refreshExpeditions() {
        do {
            let records = try expeditionManager.listExpeditions()
            expeditions = records.sorted { $0.updatedAt > $1.updatedAt }

            var assetCounts: [UUID: Int] = [:]
            var groupCounts: [UUID: Int] = [:]
            for exp in expeditions {
                assetCounts[exp.id] = (try? expeditionAssetRepo.fetchCountByExpedition(exp.id.uuidString)) ?? 0
                groupCounts[exp.id] = (try? photoGroupRepo.fetchByExpedition(exp.id.uuidString).count) ?? 0
            }
            expeditionAssetCounts = assetCounts
            expeditionGroupCounts = groupCounts
        } catch {
            Self.logger.error("Failed to refresh expeditions: \(error.localizedDescription)")
        }
    }

    var pendingFolderStorageMode: AssetStorageMode = .managed

    @discardableResult
    func createExpedition(
        name: String,
        sourceMode: ExpeditionSourceMode = .sdCard,
        defaultStorageMode: AssetStorageMode = .managed
    ) throws -> Expedition {
        pendingFolderStorageMode = defaultStorageMode
        let expedition = try expeditionManager.createExpedition(name: name, sourceMode: sourceMode)
        refreshExpeditions()
        return expedition
    }

    func deleteExpedition(id: UUID) throws {
        try expeditionManager.deleteExpedition(id)
        if case .expedition(let openId) = selectedNavItem, openId == id {
            workspaceStore?.closeExpedition()
            workspaceStore = nil
            selectedNavItem = nil
        }
        refreshExpeditions()
    }

    func renameExpedition(id: UUID, newName: String) throws {
        guard var expedition = try expeditionManager.fetchExpedition(id: id) else { return }
        expedition.name = newName
        try expeditionManager.updateExpedition(expedition)
        refreshExpeditions()
    }

    // MARK: - Navigation

    var expeditionOpenError: String?

    func openExpedition(id: UUID) {
        expeditionOpenError = nil
        workspaceStore?.closeExpedition()
        let store = ExpeditionWorkspaceStore(
            db: db,
            assetManager: assetManager,
            expeditionManager: expeditionManager,
            photoGroupRepo: photoGroupRepo,
            scoreRepo: scoreRepo
        )
        do {
            try store.openExpedition(id: id)
            workspaceStore = store
            selectedNavItem = .expedition(id)
        } catch {
            Self.logger.error("Failed to open expedition \(id): \(error.localizedDescription)")
            expeditionOpenError = error.localizedDescription
            workspaceStore = nil
        }
    }

    func leaveExpedition() {
        workspaceStore?.closeExpedition()
        workspaceStore = nil
        selectedNavItem = nil
    }

    // MARK: - Global Queries

    func refreshCounts() {
        do {
            allAssetsCount = try assetRepo.fetchCount()
            recentlyAddedAssets = try assetRepo.fetchRecentlyAdded(limit: 100).compactMap { MasterAsset(record: $0) }
            unorganizedAssets = try assetRepo.fetchUnorganized(limit: 200).compactMap { MasterAsset(record: $0) }
        } catch {
            Self.logger.error("Failed to refresh counts: \(error.localizedDescription)")
        }
    }

    func refreshAllAssets() {
        do {
            allAssets = try assetRepo.fetchAll().compactMap { MasterAsset(record: $0) }
        } catch {
            Self.logger.error("Failed to refresh all assets: \(error.localizedDescription)")
        }
    }

    // MARK: - Create Expedition from Mac Photos

    func fetchMacPhotosAssetsByDateRange(from startDate: Date, to endDate: Date) throws -> [MasterAsset] {
        let records = try assetRepo.fetchBySourceKindAndDateRange(
            AssetSourceKind.macPhotos.rawValue,
            from: startDate.timeIntervalSinceReferenceDate,
            to: endDate.timeIntervalSinceReferenceDate
        )
        return records.compactMap { MasterAsset(record: $0) }
    }

    func fetchMacPhotosCollections() async -> [PHCollectionSnapshot] {
        await macPhotosManager?.fetchCollections() ?? []
    }

    func fetchMacPhotosAssetsByCollections(_ collectionIds: [String]) async throws -> [MasterAsset] {
        guard let mgr = macPhotosManager else { return [] }
        var allIds: Set<String> = []
        for colId in collectionIds {
            let ids = await mgr.assetIdentifiers(in: colId)
            allIds.formUnion(ids)
        }
        guard !allIds.isEmpty else { return [] }
        let records = try assetRepo.fetchByExternalIds(Array(allIds))
        return records.compactMap { MasterAsset(record: $0) }
    }

    @discardableResult
    func createExpeditionFromMacPhotos(name: String, assetIds: [UUID]) throws -> Expedition {
        let expedition = try expeditionManager.createExpedition(
            name: name,
            sourceMode: .macPhotos,
            status: .reviewing,
            startDate: nil,
            endDate: nil,
            coverAssetId: nil,
            createdAt: Date(),
            isMacPhotos: false
        )
        let now = Date().timeIntervalSinceReferenceDate
        let records = assetIds.enumerated().map { index, assetId in
            ExpeditionAssetRecord(
                id: UUID().uuidString,
                expeditionId: expedition.id.uuidString,
                assetId: assetId.uuidString,
                addedAt: now,
                addedBy: AssetAddedBy.macPhotosSync.rawValue,
                localOrder: index,
                decision: "pending",
                rating: nil,
                colorLabel: nil,
                isRecommended: false,
                isBestInGroup: false,
                isUserOverride: false,
                isArchived: false,
                isHiddenInExpedition: false,
                updatedAt: now
            )
        }
        try expeditionAssetRepo.insertBatch(records)
        refreshExpeditions()
        refreshCounts()
        return expedition
    }

    // MARK: - Mac Photos Browse Data

    struct MacPhotosMonthSection: Identifiable {
        let year: Int
        let month: Int
        let assets: [MasterAsset]
        var id: Int { year * 100 + month }

        private static let titleFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.setLocalizedDateFormatFromTemplate("yyyyMMMM")
            return f
        }()

        var displayTitle: String {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            guard let date = Calendar.current.date(from: comps) else {
                return "\(year) 年 \(month) 月"
            }
            return Self.titleFormatter.string(from: date)
        }
    }

    private(set) var macPhotosMonthSections: [MacPhotosMonthSection] = []
    private(set) var macPhotosAssetsTotal: Int = 0

    func refreshMacPhotosAssets() {
        do {
            let records = try assetRepo.fetchBySourceKind(
                AssetSourceKind.macPhotos.rawValue,
                orderedBy: Column("captureDate"),
                ascending: false
            )
            let assets = records.compactMap { MasterAsset(record: $0) }
            macPhotosAssetsTotal = assets.count

            let cal = Calendar.current
            var grouped: [Int: [MasterAsset]] = [:]
            var noDateAssets: [MasterAsset] = []

            for asset in assets {
                if let date = asset.captureDate {
                    let comps = cal.dateComponents([.year, .month], from: date)
                    let key = (comps.year ?? 0) * 100 + (comps.month ?? 0)
                    grouped[key, default: []].append(asset)
                } else {
                    noDateAssets.append(asset)
                }
            }

            var sections = grouped.map { key, items in
                MacPhotosMonthSection(
                    year: key / 100,
                    month: key % 100,
                    assets: items
                )
            }
            sections.sort { $0.id > $1.id }

            if !noDateAssets.isEmpty {
                sections.append(MacPhotosMonthSection(year: 0, month: 0, assets: noDateAssets))
            }

            macPhotosMonthSections = sections
        } catch {
            Self.logger.error("Failed to refresh Mac Photos assets: \(error.localizedDescription)")
        }
    }

    // MARK: - Reference Validity

    func checkReferencedAssetValidity(expeditionId: UUID) -> [MasterAsset] {
        do {
            let masters = try assetManager.fetchAssetsForExpedition(expeditionId: expeditionId)
            return masters.filter { ma in
                guard ma.storageMode == .referenced else { return false }
                guard let url = ma.originalURL ?? ma.previewURL ?? ma.rawURL else { return true }
                return !FileManager.default.fileExists(atPath: url.path)
            }
        } catch {
            return []
        }
    }

    func relocateAsset(assetId: UUID, newURL: URL) throws {
        guard var record = try assetRepo.fetchById(assetId.uuidString) else { return }
        record.originalURL = newURL.absoluteString
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try assetRepo.update(record)
    }

    func refreshInvalidReferenceCounts() {
        for exp in expeditions {
            let invalid = checkReferencedAssetValidity(expeditionId: exp.id)
            invalidReferenceCounts[exp.id] = invalid.count
        }
    }

    // MARK: - V4 Import Pipeline

    private func makeImportPipeline() -> ImportPipeline {
        ImportPipeline(
            db: db,
            assetManager: assetManager,
            photoGroupRepo: photoGroupRepo,
            importSessionRepo: importSessionRepo
        )
    }

    func startFolderImport(expeditionId: UUID, folderURL: URL, storageMode: AssetStorageMode) async {
        let source: AssetSource
        do {
            source = try assetSourceManager.registerSource(
                kind: .localFolder,
                displayName: folderURL.lastPathComponent,
                rootIdentifier: folderURL.path
            )
        } catch {
            Self.logger.error("Failed to register folder source: \(error.localizedDescription)")
            importError = "无法注册导入源：\(error.localizedDescription)"
            return
        }
        let adapter = FolderSourceAdapter(source: source, rootFolder: folderURL, storageMode: storageMode)
        await runImportPipeline(adapter: adapter, expeditionId: expeditionId)
    }

    func startSDCardImport(expeditionId: UUID, volumeURL: URL) async {
        let source: AssetSource
        do {
            source = try assetSourceManager.registerSource(
                kind: .sdCard,
                displayName: volumeURL.lastPathComponent,
                rootIdentifier: volumeURL.path
            )
        } catch {
            Self.logger.error("Failed to register SD card source: \(error.localizedDescription)")
            importError = "无法注册导入源：\(error.localizedDescription)"
            return
        }
        let adapter = SDCardSourceAdapter(source: source, volumeURL: volumeURL)
        await runImportPipeline(adapter: adapter, expeditionId: expeditionId)
    }

    func dismissImportError() {
        importError = nil
    }

    private func runImportPipeline(adapter: any AssetSourceAdapter, expeditionId: UUID) async {
        isImporting = true
        importError = nil
        importProgress = ImportProgress(phase: .scanning, completed: 0, total: 1, currentItemName: adapter.displayName)

        let pipeline = makeImportPipeline()
        do {
            let result = try await pipeline.addPhotosToExpedition(
                adapter: adapter,
                expeditionId: expeditionId
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.importProgress = progress
                }
            }
            Self.logger.log(
                "Import completed: \(result.importedAssets.count) assets, \(result.groupCount) groups"
            )
        } catch {
            Self.logger.error("Import failed: \(error.localizedDescription)")
            importError = "导入失败：\(error.localizedDescription)"
        }

        isImporting = false
        importProgress = nil
        refreshExpeditions()
        refreshCounts()
        refreshInvalidReferenceCounts()

        if case .expedition(let openId) = selectedNavItem, openId == expeditionId {
            workspaceStore?.closeExpedition()
            openExpedition(id: expeditionId)
        }
    }
}
