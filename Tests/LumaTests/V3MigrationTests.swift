import Foundation
import GRDB
import Testing
@testable import Luma

@Suite("V3MigrationManager")
struct V3MigrationTests {

    private func makeTestDeps() throws -> (
        db: LumaDatabase,
        migrationManager: V3MigrationManager,
        assetManager: AssetManager,
        expeditionManager: ExpeditionManager,
        scoreRepo: GRDBAssetScoreRepository,
        groupRepo: GRDBPhotoGroupRepository,
        importSessionRepo: GRDBImportSessionRepository,
        assetRepo: GRDBMasterAssetRepository
    ) {
        let db = try LumaDatabase.inMemory()
        let assetRepo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)
        let expAssetRepo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)
        let assetMgr = AssetManager(db: db, assetRepo: assetRepo, expeditionAssetRepo: expAssetRepo)
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let sourceMgr = AssetSourceManager(db: db)
        let groupRepo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)
        let scoreRepo = GRDBAssetScoreRepository(dbQueue: db.dbQueue)
        let importSessionRepo = GRDBImportSessionRepository(dbQueue: db.dbQueue)
        let mgr = V3MigrationManager(
            db: db,
            assetSourceManager: sourceMgr,
            expeditionManager: expMgr,
            assetManager: assetMgr,
            photoGroupRepo: groupRepo,
            scoreRepo: scoreRepo,
            importSessionRepo: importSessionRepo
        )
        return (db, mgr, assetMgr, expMgr, scoreRepo, groupRepo, importSessionRepo, assetRepo)
    }

    private func createTestManifest(
        assetCount: Int = 3,
        withScore: Bool = true,
        withGroups: Bool = true
    ) -> (SessionManifest, [UUID]) {
        let sessionId = UUID()
        var assets: [MediaAsset] = []
        var assetIds: [UUID] = []

        for i in 0..<assetCount {
            let id = UUID()
            assetIds.append(id)
            let score: AIScore? = withScore ? AIScore(
                provider: "test_provider",
                scores: PhotoScores(composition: 80, exposure: 75, color: 70, sharpness: 85, story: 65),
                overall: 75,
                comment: "Test comment \(i)",
                recommended: i == 0,
                timestamp: Date()
            ) : nil
            let asset = MediaAsset(
                id: id,
                importResumeKey: "key_\(i)",
                baseName: "IMG_\(1000 + i)",
                source: .folder(path: "/test/photos"),
                previewURL: nil,
                rawURL: nil,
                livePhotoVideoURL: nil,
                depthData: false,
                thumbnailURL: nil,
                metadata: EXIFData(
                    captureDate: Date(timeIntervalSince1970: 1700000000 + Double(i * 3600)),
                    gpsCoordinate: nil,
                    focalLength: 35.0,
                    aperture: 2.8,
                    shutterSpeed: "1/250",
                    iso: 400,
                    cameraModel: "TestCam",
                    lensModel: "TestLens",
                    imageWidth: 6000,
                    imageHeight: 4000
                ),
                mediaType: .photo,
                importState: .complete,
                aiScore: score,
                editSuggestions: nil,
                userDecision: i == 0 ? .picked : (i == 1 ? .rejected : .pending),
                userRating: i == 0 ? 5 : nil,
                issues: []
            )
            assets.append(asset)
        }

        var groups: [PhotoGroup] = []
        if withGroups && assetCount >= 2 {
            let group = PhotoGroup(
                id: UUID(),
                name: "Test Group",
                assets: Array(assetIds.prefix(2)),
                subGroups: [
                    SubGroup(id: UUID(), assets: Array(assetIds.prefix(2)), bestAsset: assetIds[0])
                ],
                timeRange: Date(timeIntervalSince1970: 1700000000)...Date(timeIntervalSince1970: 1700003600),
                location: Coordinate(latitude: 35.6762, longitude: 139.6503),
                groupComment: "Test group comment",
                recommendedAssets: [assetIds[0]]
            )
            groups.append(group)
        }

        let manifest = SessionManifest(
            id: sessionId,
            name: "Test Trip 2026",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            assets: assets,
            groups: groups,
            importSessions: [],
            editingSessions: [],
            exportJobs: []
        )
        return (manifest, assetIds)
    }

    private func runMigration(
        deps: (db: LumaDatabase, migrationManager: V3MigrationManager, assetManager: AssetManager,
               expeditionManager: ExpeditionManager, scoreRepo: GRDBAssetScoreRepository,
               groupRepo: GRDBPhotoGroupRepository, importSessionRepo: GRDBImportSessionRepository,
               assetRepo: GRDBMasterAssetRepository),
        manifest: SessionManifest
    ) throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var sourceCache: [String: AssetSource] = [:]
        var hashIndex: [String: UUID] = [:]
        try deps.migrationManager.migrateOneSession(
            manifest: manifest,
            projectDirectory: tmpDir,
            sourceCache: &sourceCache,
            masterAssetHashIndex: &hashIndex,
            onAssetProgress: { _, _ in }
        )
    }

    @Test("migrateOneSession creates Expedition with correct name")
    func testMigrateCreatesExpedition() throws {
        let deps = try makeTestDeps()
        let (manifest, _) = createTestManifest()
        try runMigration(deps: deps, manifest: manifest)

        let expeditions = try deps.expeditionManager.listExpeditions()
        #expect(expeditions.count == 1)
        #expect(expeditions[0].name == "Test Trip 2026")
    }

    @Test("migrateOneSession migrates decisions and ratings correctly")
    func testMigrateDecisionsAndRatings() throws {
        let deps = try makeTestDeps()
        let (manifest, assetIds) = createTestManifest()
        try runMigration(deps: deps, manifest: manifest)

        let expeditions = try deps.expeditionManager.listExpeditions()
        let expId = expeditions[0].id

        let expAssets = try deps.db.dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expId.uuidString)
                .fetchAll(db)
        }
        #expect(expAssets.count == 3)

        let pickedAsset = expAssets.first { $0.assetId == assetIds[0].uuidString }
        #expect(pickedAsset?.decision == "picked")
        #expect(pickedAsset?.rating == 5)
        #expect(pickedAsset?.isRecommended == true)

        let rejectedAsset = expAssets.first { $0.assetId == assetIds[1].uuidString }
        #expect(rejectedAsset?.decision == "rejected")

        let pendingAsset = expAssets.first { $0.assetId == assetIds[2].uuidString }
        #expect(pendingAsset?.decision == "pending")
    }

    @Test("migrateOneSession migrates AI scores")
    func testMigrateAIScores() throws {
        let deps = try makeTestDeps()
        let (manifest, assetIds) = createTestManifest(withScore: true)
        try runMigration(deps: deps, manifest: manifest)

        for assetId in assetIds {
            let score = try deps.scoreRepo.fetchLatestByAsset(assetId.uuidString)
            #expect(score != nil)
            #expect(score?.provider == "test_provider")
            #expect(score?.overall == 75)
            #expect(score?.composition == 80)
        }
    }

    @Test("migrateOneSession migrates groups and subgroups")
    func testMigrateGroups() throws {
        let deps = try makeTestDeps()
        let (manifest, _) = createTestManifest(withGroups: true)
        try runMigration(deps: deps, manifest: manifest)

        let expeditions = try deps.expeditionManager.listExpeditions()
        let expId = expeditions[0].id

        let groups = try deps.groupRepo.fetchByExpedition(expId.uuidString)
        #expect(groups.count == 1)
        #expect(groups[0].name == "Test Group")

        let groupAssets = try deps.groupRepo.fetchAssetsForGroup(groups[0].id)
        #expect(groupAssets.count == 2)

        let recommendedInGroup = groupAssets.filter(\.isRecommended)
        #expect(recommendedInGroup.count == 1)
    }

    @Test("migrateOneSession registers AssetSource for folder")
    func testMigrateRegistersSource() throws {
        let deps = try makeTestDeps()
        let (manifest, _) = createTestManifest(assetCount: 1)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var sourceCache: [String: AssetSource] = [:]
        var hashIndex: [String: UUID] = [:]
        try deps.migrationManager.migrateOneSession(
            manifest: manifest,
            projectDirectory: tmpDir,
            sourceCache: &sourceCache,
            masterAssetHashIndex: &hashIndex,
            onAssetProgress: { _, _ in }
        )

        #expect(sourceCache.count == 1)
        let source = sourceCache.values.first!
        #expect(source.kind == .localFolder)
    }

    @Test("migrateOneSession handles no-score assets")
    func testMigrateNoScore() throws {
        let deps = try makeTestDeps()
        let (manifest, assetIds) = createTestManifest(assetCount: 2, withScore: false, withGroups: false)
        try runMigration(deps: deps, manifest: manifest)

        for assetId in assetIds {
            let score = try deps.scoreRepo.fetchLatestByAsset(assetId.uuidString)
            #expect(score == nil)
        }
    }

    @Test("migrateOneSession infers completed status when all assets decided")
    func testInferCompletedStatus() throws {
        let deps = try makeTestDeps()
        let (manifest, _) = createTestManifest(assetCount: 2, withScore: false, withGroups: false)
        var updatedManifest = manifest
        var session = updatedManifest.session
        for i in 0..<session.assets.count {
            session.assets[i].userDecision = .picked
        }
        updatedManifest.session = session

        try runMigration(deps: deps, manifest: updatedManifest)

        let expeditions = try deps.expeditionManager.listExpeditions()
        #expect(expeditions[0].status == .completed)
    }

    @Test("migrateOneSession preserves MasterAsset UUID from MediaAsset")
    func testUUIDPreservation() throws {
        let deps = try makeTestDeps()
        let (manifest, assetIds) = createTestManifest(assetCount: 1, withScore: false, withGroups: false)
        try runMigration(deps: deps, manifest: manifest)

        let masterRecord = try deps.assetRepo.fetchById(assetIds[0].uuidString)
        #expect(masterRecord != nil)
        #expect(masterRecord?.id == assetIds[0].uuidString)
    }
}
