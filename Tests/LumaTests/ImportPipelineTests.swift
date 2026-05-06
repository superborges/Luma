import CoreGraphics
import XCTest
import GRDB
@testable import Luma

private struct MockAssetSourceAdapter: AssetSourceAdapter {
    let source: AssetSource
    let items: [DiscoveredAsset]
    let thumbnailImage: CGImage?
    var previewFiles: [UUID: URL]
    var originalFiles: [UUID: URL]

    var displayName: String { source.displayName }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.finish()
        }
    }

    func enumerateAssets(options: SourceEnumerationOptions) async throws -> [DiscoveredAsset] {
        items.filter { asset in
            if let filter = options.mediaTypeFilter, !filter.contains(asset.mediaType) { return false }
            if let dateRange = options.dateRange, !dateRange.contains(asset.metadata.captureDate) { return false }
            return true
        }
    }

    func fetchThumbnail(_ asset: DiscoveredAsset, size: CGSize) async throws -> CGImage? {
        thumbnailImage
    }

    func fetchPreview(_ asset: DiscoveredAsset) async throws -> URL? {
        previewFiles[asset.id]
    }

    func fetchOriginal(_ asset: DiscoveredAsset) async throws -> URL? {
        originalFiles[asset.id]
    }

    func supports(_ capability: SourceCapability) -> Bool {
        true
    }
}

private final class SendableBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    init(_ value: T) {
        _value = value
    }

    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&_value)
    }
}

final class ImportPipelineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportPipelineTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        setenv("LUMA_APP_SUPPORT_ROOT", tempDir.path, 1)
    }

    override func tearDown() {
        unsetenv("LUMA_APP_SUPPORT_ROOT")
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeEnv() throws -> (
        LumaDatabase, AssetManager, AssetSourceManager,
        GRDBPhotoGroupRepository, GRDBImportSessionRepository, ImportPipeline
    ) {
        let db = try LumaDatabase.inMemory()
        let assetRepo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)
        let expAssetRepo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)
        let assetMgr = AssetManager(db: db, assetRepo: assetRepo, expeditionAssetRepo: expAssetRepo)
        let sourceMgr = AssetSourceManager(db: db)
        let groupRepo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)
        let sessionRepo = GRDBImportSessionRepository(dbQueue: db.dbQueue)
        let pipeline = ImportPipeline(
            db: db,
            assetManager: assetMgr,
            photoGroupRepo: groupRepo,
            importSessionRepo: sessionRepo,
            groupingEngine: GroupingEngine()
        )
        return (db, assetMgr, sourceMgr, groupRepo, sessionRepo, pipeline)
    }

    private func makeSource(_ sourceMgr: AssetSourceManager) throws -> AssetSource {
        try sourceMgr.registerSource(kind: .sdCard, displayName: "TestSD", rootIdentifier: "/Volumes/TestSD")
    }

    private func makeDiscoveredAssets(count: Int, sourceKind: AssetSourceKind = .sdCard) -> [DiscoveredAsset] {
        (0..<count).map { i in
            DiscoveredAsset(
                baseName: "IMG_\(String(format: "%04d", i))",
                sourceKind: sourceKind,
                metadata: EXIFData(
                    captureDate: Date(timeIntervalSince1970: Double(1700000000 + i * 60)),
                    gpsCoordinate: nil,
                    focalLength: nil,
                    aperture: nil,
                    shutterSpeed: nil,
                    iso: nil,
                    cameraModel: nil,
                    lensModel: nil,
                    imageWidth: 4000,
                    imageHeight: 3000
                ),
                mediaType: .photo,
                suggestedStorageMode: .managed,
                contentHashHint: "hash_\(i)"
            )
        }
    }

    // MARK: - Tests

    func testImportCreatesAssetsAndExpeditionAssets() async throws {
        let (db, assetMgr, sourceMgr, _, _, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Test", sourceMode: .sdCard)
        let source = try makeSource(sourceMgr)

        let items = makeDiscoveredAssets(count: 3)
        let adapter = MockAssetSourceAdapter(
            source: source, items: items,
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let result = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.importedAssets.count, 3)
        XCTAssertEqual(result.createdExpeditionAssets.count, 3)
        XCTAssertEqual(result.duplicateCount, 0)

        let allAssets = try assetMgr.fetchAssetsForExpedition(expeditionId: expedition.id)
        XCTAssertEqual(allAssets.count, 3)
    }

    func testImportDeduplicatesByContentHash() async throws {
        let (db, _, sourceMgr, _, _, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Dedup", sourceMode: .sdCard)
        let source = try makeSource(sourceMgr)

        let items = [
            DiscoveredAsset(
                baseName: "IMG_0001",
                sourceKind: .sdCard,
                metadata: EXIFData(
                    captureDate: Date(timeIntervalSince1970: 1700000000),
                    gpsCoordinate: nil, focalLength: nil, aperture: nil,
                    shutterSpeed: nil, iso: nil, cameraModel: nil, lensModel: nil,
                    imageWidth: 4000, imageHeight: 3000
                ),
                mediaType: .photo,
                suggestedStorageMode: .managed,
                contentHashHint: "same_hash"
            ),
            DiscoveredAsset(
                baseName: "IMG_0002",
                sourceKind: .sdCard,
                metadata: EXIFData(
                    captureDate: Date(timeIntervalSince1970: 1700000060),
                    gpsCoordinate: nil, focalLength: nil, aperture: nil,
                    shutterSpeed: nil, iso: nil, cameraModel: nil, lensModel: nil,
                    imageWidth: 4000, imageHeight: 3000
                ),
                mediaType: .photo,
                suggestedStorageMode: .managed,
                contentHashHint: "same_hash"
            )
        ]

        let adapter = MockAssetSourceAdapter(
            source: source, items: items,
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let result = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.importedAssets.count, 2)
        XCTAssertEqual(result.duplicateCount, 1, "Second asset with same hash should count as duplicate")
        XCTAssertEqual(result.importedAssets[0].id, result.importedAssets[1].id,
                        "Both should reference the same MasterAsset")
    }

    func testImportEmptySourceCreatesNoAssets() async throws {
        let (db, _, sourceMgr, _, sessionRepo, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Empty", sourceMode: .sdCard)
        let source = try makeSource(sourceMgr)

        let adapter = MockAssetSourceAdapter(
            source: source, items: [],
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let result = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { _ in }
        )

        XCTAssertTrue(result.importedAssets.isEmpty)
        XCTAssertEqual(result.groupCount, 0)

        let sessions = try sessionRepo.fetchByExpedition(expedition.id.uuidString)
        XCTAssertEqual(sessions.count, 1, "Should still create an ImportSession record")
        XCTAssertEqual(sessions.first?.status, "completed")
    }

    func testImportCreatesPhotoGroupRecords() async throws {
        let (db, _, sourceMgr, groupRepo, _, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Groups", sourceMode: .sdCard)
        let source = try makeSource(sourceMgr)

        let items = makeDiscoveredAssets(count: 5)
        let adapter = MockAssetSourceAdapter(
            source: source, items: items,
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let result = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { _ in }
        )

        XCTAssertGreaterThan(result.groupCount, 0)

        let dbGroups = try groupRepo.fetchByExpedition(expedition.id.uuidString)
        XCTAssertEqual(dbGroups.count, result.groupCount)

        var totalGroupAssets = 0
        for group in dbGroups {
            let assets = try groupRepo.fetchAssetsForGroup(group.id)
            totalGroupAssets += assets.count
        }
        XCTAssertEqual(totalGroupAssets, 5, "All 5 assets should be assigned to groups")
    }

    func testImportCreatesImportSessionRecord() async throws {
        let (db, _, sourceMgr, _, sessionRepo, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Session", sourceMode: .sdCard)
        let source = try makeSource(sourceMgr)

        let items = makeDiscoveredAssets(count: 2)
        let adapter = MockAssetSourceAdapter(
            source: source, items: items,
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let result = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { _ in }
        )

        let sessions = try sessionRepo.fetchByExpedition(expedition.id.uuidString)
        XCTAssertEqual(sessions.count, 1)

        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.id, result.sessionId.uuidString)
        XCTAssertEqual(session.sourceId, source.id.uuidString)
        XCTAssertEqual(session.totalItems, 2)
        XCTAssertEqual(session.status, "completed")
    }

    func testImportProgressCallbackPhases() async throws {
        let (db, _, sourceMgr, _, _, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Progress", sourceMode: .sdCard)
        let source = try makeSource(sourceMgr)

        let items = makeDiscoveredAssets(count: 2)
        let adapter = MockAssetSourceAdapter(
            source: source, items: items,
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let phasesBox = SendableBox<[ImportPhase]>([])
        _ = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { progress in
                phasesBox.mutate { $0.append(progress.phase) }
            }
        )
        let phases = phasesBox.value

        let uniquePhases = phases.reduce(into: [ImportPhase]()) { result, phase in
            if result.last != phase { result.append(phase) }
        }

        XCTAssertTrue(uniquePhases.contains(.scanning))
        XCTAssertTrue(uniquePhases.contains(.preparingThumbnails))
        XCTAssertTrue(uniquePhases.contains(.copyingPreviews))
        XCTAssertTrue(uniquePhases.contains(.copyingOriginals))
        XCTAssertTrue(uniquePhases.contains(.finalizing))
    }

    func testReferencedModeDoesNotCopyFiles() async throws {
        let (db, _, sourceMgr, _, _, pipeline) = try makeEnv()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let expedition = try expMgr.createExpedition(name: "Referenced", sourceMode: .localFolder)

        let folderSource = try sourceMgr.registerSource(
            kind: .localFolder, displayName: "MyFolder", rootIdentifier: "/photos"
        )

        let originalPreviewURL = URL(fileURLWithPath: "/photos/IMG_0001.jpg")
        let originalRawURL = URL(fileURLWithPath: "/photos/IMG_0001.arw")

        let items = [
            DiscoveredAsset(
                baseName: "IMG_0001",
                sourceKind: .localFolder,
                previewFileURL: originalPreviewURL,
                rawFileURL: originalRawURL,
                metadata: EXIFData(
                    captureDate: Date(timeIntervalSince1970: 1700000000),
                    gpsCoordinate: nil, focalLength: nil, aperture: nil,
                    shutterSpeed: nil, iso: nil, cameraModel: nil, lensModel: nil,
                    imageWidth: 4000, imageHeight: 3000
                ),
                mediaType: .photo,
                suggestedStorageMode: .referenced,
                contentHashHint: nil
            )
        ]

        let adapter = MockAssetSourceAdapter(
            source: folderSource, items: items,
            thumbnailImage: nil, previewFiles: [:], originalFiles: [:]
        )

        let result = try await pipeline.addPhotosToExpedition(
            adapter: adapter,
            expeditionId: expedition.id,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.importedAssets.count, 1)
        let asset = result.importedAssets[0]
        XCTAssertEqual(asset.previewURL, originalPreviewURL,
                        "Referenced mode: previewURL should point to original location")
        XCTAssertEqual(asset.rawURL, originalRawURL,
                        "Referenced mode: rawURL should point to original location")
        XCTAssertNil(asset.localManagedURL,
                     "Referenced mode: should not have localManagedURL")
    }

    func testGroupingEngineAdapterForMasterAssets() async throws {
        let engine = GroupingEngine()
        let now = Date()

        let masterAssets = (0..<5).compactMap { i in
            MasterAsset(record: MasterAssetRecord(
                id: UUID().uuidString,
                sourceId: nil,
                sourceKind: AssetSourceKind.sdCard.rawValue,
                storageMode: AssetStorageMode.managed.rawValue,
                externalIdentifier: nil,
                originalURL: nil, localManagedURL: nil, previewURL: nil,
                rawURL: nil, livePhotoVideoURL: nil,
                thumbnailCacheURL: nil, previewCacheURL: nil,
                fingerprint: nil, contentHash: "h\(i)",
                baseName: "IMG_\(i)",
                mediaType: MediaType.photo.rawValue,
                captureDate: now.addingTimeInterval(Double(i * 60)).timeIntervalSinceReferenceDate,
                latitude: nil, longitude: nil,
                focalLength: nil, aperture: nil, shutterSpeed: nil, iso: nil,
                cameraModel: nil, lensModel: nil,
                imageWidth: 4000, imageHeight: 3000,
                createdAt: now.timeIntervalSinceReferenceDate,
                updatedAt: now.timeIntervalSinceReferenceDate
            ))
        }

        let groups = await engine.makeGroupsFromMasterAssets(masterAssets, resolvesLocationNames: false)
        XCTAssertGreaterThan(groups.count, 0, "Should produce at least one group")

        let totalAssetIds = groups.flatMap(\.assets)
        XCTAssertEqual(totalAssetIds.count, 5, "All assets should be in groups")
    }
}
