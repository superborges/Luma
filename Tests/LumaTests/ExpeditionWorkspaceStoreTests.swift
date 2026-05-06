import XCTest
import GRDB
@testable import Luma

@MainActor
final class ExpeditionWorkspaceStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceStoreTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        setenv("LUMA_APP_SUPPORT_ROOT", tempDir.path, 1)
    }

    override func tearDown() {
        unsetenv("LUMA_APP_SUPPORT_ROOT")
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEnv() throws -> (
        LumaDatabase, AssetManager, ExpeditionManager,
        GRDBPhotoGroupRepository, GRDBAssetScoreRepository,
        ExpeditionWorkspaceStore
    ) {
        let db = try LumaDatabase.inMemory()
        let assetRepo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)
        let expAssetRepo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)
        let assetMgr = AssetManager(db: db, assetRepo: assetRepo, expeditionAssetRepo: expAssetRepo)
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let groupRepo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)
        let scoreRepo = GRDBAssetScoreRepository(dbQueue: db.dbQueue)
        let store = ExpeditionWorkspaceStore(
            db: db,
            assetManager: assetMgr,
            expeditionManager: expMgr,
            photoGroupRepo: groupRepo,
            scoreRepo: scoreRepo
        )
        return (db, assetMgr, expMgr, groupRepo, scoreRepo, store)
    }

    private func seedExpeditionWithAssets(
        db: LumaDatabase,
        assetMgr: AssetManager,
        expMgr: ExpeditionManager,
        groupRepo: GRDBPhotoGroupRepository,
        count: Int = 5
    ) throws -> (Expedition, [MasterAsset]) {
        let exp = try expMgr.createExpedition(name: "Test Expedition", sourceMode: .sdCard)
        let sourceMgr = AssetSourceManager(db: db)
        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "SD", rootIdentifier: "/vol/sd")
        let now = Date()

        var masterAssets: [MasterAsset] = []
        for i in 0..<count {
            let ma = try assetMgr.createOrReuseMasterAsset(
                baseName: "IMG_\(String(format: "%04d", i))",
                mediaType: .photo,
                sourceKind: .sdCard,
                storageMode: .managed,
                sourceId: source.id,
                externalIdentifier: nil,
                contentHash: "hash_\(i)",
                originalURL: nil,
                metadata: EXIFData(
                    captureDate: now.addingTimeInterval(Double(i * 60)),
                    gpsCoordinate: nil, focalLength: nil, aperture: nil,
                    shutterSpeed: nil, iso: nil, cameraModel: "Canon R5", lensModel: nil,
                    imageWidth: 4000, imageHeight: 3000
                )
            )
            _ = try assetMgr.addAssetToExpedition(
                assetId: ma.id, expeditionId: exp.id, addedBy: .importSession(UUID().uuidString)
            )
            masterAssets.append(ma)
        }

        let groupNow = Date().timeIntervalSinceReferenceDate
        let groupRecord = PhotoGroupRecord(
            id: UUID().uuidString,
            expeditionId: exp.id.uuidString,
            name: "Test Group",
            coverAssetId: nil,
            groupComment: nil,
            timeRangeStart: now.timeIntervalSinceReferenceDate,
            timeRangeEnd: now.addingTimeInterval(Double(count * 60)).timeIntervalSinceReferenceDate,
            latitude: nil, longitude: nil,
            reviewed: false, createdAt: groupNow, updatedAt: groupNow
        )
        try groupRepo.insert(groupRecord)
        for ma in masterAssets {
            let assetRecord = PhotoGroupAssetRecord(
                groupId: groupRecord.id,
                assetId: ma.id.uuidString,
                isRecommended: false
            )
            try groupRepo.addAsset(assetRecord)
        }

        return (exp, masterAssets)
    }

    // MARK: - Tests

    func testOpenExpeditionLoadsAssetsAndGroups() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, _) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)

        XCTAssertNotNil(store.currentExpedition)
        XCTAssertEqual(store.currentExpedition?.id, exp.id)
        XCTAssertEqual(store.expeditionAssets.count, 5)
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups.first?.assetCount, 5)
        XCTAssertEqual(store.totalCount, 5)
        XCTAssertEqual(store.pendingCount, 5)
        XCTAssertNotNil(store.selectedAssetId)
    }

    func testCloseExpeditionClearsState() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, _) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        store.closeExpedition()

        XCTAssertNil(store.currentExpedition)
        XCTAssertTrue(store.expeditionAssets.isEmpty)
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertNil(store.selectedAssetId)
        XCTAssertNil(store.selectedGroupId)
    }

    func testSetDecisionUpdatesAsset() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let assetId = masterAssets[0].id

        try store.setDecision(assetId: assetId, decision: .picked)

        XCTAssertEqual(store.pickedCount, 1)
        XCTAssertEqual(store.pendingCount, 4)

        let asset = store.expeditionAssets.first(where: { $0.assetId == assetId })
        XCTAssertEqual(asset?.decision, .picked)
    }

    func testTogglePicked() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let assetId = masterAssets[0].id

        try store.togglePicked(assetId: assetId)
        XCTAssertEqual(store.expeditionAssets.first(where: { $0.assetId == assetId })?.decision, .picked)

        try store.togglePicked(assetId: assetId)
        XCTAssertEqual(store.expeditionAssets.first(where: { $0.assetId == assetId })?.decision, .pending)
    }

    func testSetRating() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let assetId = masterAssets[0].id

        try store.setRating(assetId: assetId, rating: 4)

        let asset = store.expeditionAssets.first(where: { $0.assetId == assetId })
        XCTAssertEqual(asset?.rating, 4)
    }

    func testSmartFilterAll() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        try store.setDecision(assetId: masterAssets[0].id, decision: .picked)
        try store.setDecision(assetId: masterAssets[1].id, decision: .rejected)

        store.activeFilter = .all
        store.selectGroup(id: nil)
        XCTAssertEqual(store.visibleAssets.count, 5)

        store.activeFilter = .picked
        XCTAssertEqual(store.visibleAssets.count, 1)

        store.activeFilter = .rejected
        XCTAssertEqual(store.visibleAssets.count, 1)

        store.activeFilter = .pending
        XCTAssertEqual(store.visibleAssets.count, 3)
    }

    func testMoveSelection() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, _) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        store.selectGroup(id: nil)
        store.activeFilter = .all
        store.selectAsset(id: store.visibleAssets.first?.assetId)

        let firstAssetId = store.selectedAssetId
        store.moveSelection(by: 1)
        XCTAssertNotEqual(store.selectedAssetId, firstAssetId)

        store.moveSelection(by: -1)
        XCTAssertEqual(store.selectedAssetId, firstAssetId)
    }

    func testMergeGroups() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let exp = try expMgr.createExpedition(name: "MergeTest", sourceMode: .sdCard)
        let sourceMgr = AssetSourceManager(db: db)
        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "SD", rootIdentifier: "/vol/sd2")
        let now = Date()

        var allAssets: [MasterAsset] = []
        for i in 0..<6 {
            let ma = try assetMgr.createOrReuseMasterAsset(
                baseName: "IMG_\(i)", mediaType: .photo, sourceKind: .sdCard,
                storageMode: .managed, sourceId: source.id,
                externalIdentifier: nil, contentHash: "merge_\(i)", originalURL: nil,
                metadata: EXIFData(
                    captureDate: now.addingTimeInterval(Double(i * 60)),
                    gpsCoordinate: nil, focalLength: nil, aperture: nil,
                    shutterSpeed: nil, iso: nil, cameraModel: nil, lensModel: nil,
                    imageWidth: 4000, imageHeight: 3000
                )
            )
            _ = try assetMgr.addAssetToExpedition(
                assetId: ma.id, expeditionId: exp.id, addedBy: .importSession(UUID().uuidString)
            )
            allAssets.append(ma)
        }

        let groupNow = now.timeIntervalSinceReferenceDate
        let g1Id = UUID().uuidString
        let g2Id = UUID().uuidString
        try groupRepo.insert(PhotoGroupRecord(
            id: g1Id, expeditionId: exp.id.uuidString, name: "Group A",
            coverAssetId: nil, groupComment: nil,
            timeRangeStart: groupNow, timeRangeEnd: groupNow + 180,
            latitude: nil, longitude: nil, reviewed: false,
            createdAt: groupNow, updatedAt: groupNow
        ))
        try groupRepo.insert(PhotoGroupRecord(
            id: g2Id, expeditionId: exp.id.uuidString, name: "Group B",
            coverAssetId: nil, groupComment: nil,
            timeRangeStart: groupNow + 180, timeRangeEnd: groupNow + 360,
            latitude: nil, longitude: nil, reviewed: false,
            createdAt: groupNow, updatedAt: groupNow
        ))
        for i in 0..<3 {
            try groupRepo.addAsset(PhotoGroupAssetRecord(
                groupId: g1Id, assetId: allAssets[i].id.uuidString, isRecommended: false
            ))
        }
        for i in 3..<6 {
            try groupRepo.addAsset(PhotoGroupAssetRecord(
                groupId: g2Id, assetId: allAssets[i].id.uuidString, isRecommended: false
            ))
        }

        try store.openExpedition(id: exp.id)
        XCTAssertEqual(store.groups.count, 2)

        let groupIds = store.groups.map(\.id)
        try store.mergeGroups(ids: groupIds)

        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups.first?.assetCount, 6)
        XCTAssertEqual(store.groups.first?.name, "Group A")
    }

    func testSplitGroup() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let groupId = store.groups.first!.id
        let splitIds: Set<UUID> = [masterAssets[3].id, masterAssets[4].id]

        try store.splitGroup(groupId: groupId, assetIds: splitIds)

        XCTAssertEqual(store.groups.count, 2)
        let originalGroup = store.groups.first(where: { $0.id == groupId })
        let newGroup = store.groups.first(where: { $0.id != groupId })
        XCTAssertEqual(originalGroup?.assetCount, 3)
        XCTAssertEqual(newGroup?.assetCount, 2)
        XCTAssertTrue(newGroup?.name.contains("拆分") == true)
    }

    func testRemoveFromGroup() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let groupId = store.groups.first!.id

        try store.removeFromGroup(groupId: groupId, assetIds: [masterAssets[0].id])

        XCTAssertEqual(store.groups.first?.assetCount, 4)
    }

    func testRenameGroup() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, _) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let groupId = store.groups.first!.id

        try store.renameGroup(groupId: groupId, newName: "清水寺日落")

        XCTAssertEqual(store.groups.first?.name, "清水寺日落")
    }

    func testSetGroupCover() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let groupId = store.groups.first!.id

        try store.setGroupCover(groupId: groupId, assetId: masterAssets[2].id)

        XCTAssertEqual(store.groups.first?.coverAssetId, masterAssets[2].id)
    }

    func testMoveToGroup() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let exp = try expMgr.createExpedition(name: "MoveTest", sourceMode: .sdCard)
        let sourceMgr = AssetSourceManager(db: db)
        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "SD", rootIdentifier: "/vol/sd3")
        let now = Date()

        var allAssets: [MasterAsset] = []
        for i in 0..<4 {
            let ma = try assetMgr.createOrReuseMasterAsset(
                baseName: "IMG_\(i)", mediaType: .photo, sourceKind: .sdCard,
                storageMode: .managed, sourceId: source.id,
                externalIdentifier: nil, contentHash: "move_\(i)", originalURL: nil,
                metadata: EXIFData(
                    captureDate: now.addingTimeInterval(Double(i * 60)),
                    gpsCoordinate: nil, focalLength: nil, aperture: nil,
                    shutterSpeed: nil, iso: nil, cameraModel: nil, lensModel: nil,
                    imageWidth: 4000, imageHeight: 3000
                )
            )
            _ = try assetMgr.addAssetToExpedition(
                assetId: ma.id, expeditionId: exp.id, addedBy: .importSession(UUID().uuidString)
            )
            allAssets.append(ma)
        }

        let groupNow = now.timeIntervalSinceReferenceDate
        let gA = UUID().uuidString
        let gB = UUID().uuidString
        try groupRepo.insert(PhotoGroupRecord(
            id: gA, expeditionId: exp.id.uuidString, name: "Source",
            coverAssetId: nil, groupComment: nil,
            timeRangeStart: groupNow, timeRangeEnd: groupNow + 120,
            latitude: nil, longitude: nil, reviewed: false,
            createdAt: groupNow, updatedAt: groupNow
        ))
        try groupRepo.insert(PhotoGroupRecord(
            id: gB, expeditionId: exp.id.uuidString, name: "Target",
            coverAssetId: nil, groupComment: nil,
            timeRangeStart: groupNow + 120, timeRangeEnd: groupNow + 240,
            latitude: nil, longitude: nil, reviewed: false,
            createdAt: groupNow, updatedAt: groupNow
        ))
        for i in 0..<2 {
            try groupRepo.addAsset(PhotoGroupAssetRecord(
                groupId: gA, assetId: allAssets[i].id.uuidString, isRecommended: false
            ))
        }
        for i in 2..<4 {
            try groupRepo.addAsset(PhotoGroupAssetRecord(
                groupId: gB, assetId: allAssets[i].id.uuidString, isRecommended: false
            ))
        }

        try store.openExpedition(id: exp.id)
        let targetGroupId = store.groups.first(where: { $0.name == "Target" })!.id

        try store.moveToGroup(assetIds: [allAssets[0].id], targetGroupId: targetGroupId)

        let sourceGroup = store.groups.first(where: { $0.name == "Source" })
        let targetGroup = store.groups.first(where: { $0.name == "Target" })
        XCTAssertEqual(sourceGroup?.assetCount, 1)
        XCTAssertEqual(targetGroup?.assetCount, 3)
    }

    func testSetRecommendation() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        let assetId = masterAssets[0].id

        try assetMgr.setRecommendation(expeditionId: exp.id, assetId: assetId, isRecommended: true)
        try store.openExpedition(id: exp.id)

        let asset = store.expeditionAssets.first(where: { $0.assetId == assetId })
        XCTAssertTrue(asset?.isRecommended == true)
    }

    func testScoreRecordPopulatesLatestScore() throws {
        let (db, assetMgr, expMgr, groupRepo, scoreRepo, store) = try makeEnv()
        let (exp, masterAssets) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        let record = AssetScoreRecord(
            id: UUID().uuidString,
            assetId: masterAssets[0].id.uuidString,
            provider: "local_ml",
            composition: 80, exposure: 75, color: 70, sharpness: 85, story: 65,
            overall: 78,
            comment: "Good shot", recommended: true,
            timestamp: Date().timeIntervalSinceReferenceDate
        )
        try scoreRepo.insert(record)

        try store.openExpedition(id: exp.id)

        let asset = store.expeditionAssets.first(where: { $0.assetId == masterAssets[0].id })
        XCTAssertNotNil(asset?.latestScore)
        XCTAssertEqual(asset?.latestScore?.overall, 78)
        XCTAssertEqual(asset?.latestScore?.provider, "local_ml")
    }

    func testSelectAllPhotosOverview() throws {
        let (db, assetMgr, expMgr, groupRepo, _, store) = try makeEnv()
        let (exp, _) = try seedExpeditionWithAssets(
            db: db, assetMgr: assetMgr, expMgr: expMgr, groupRepo: groupRepo
        )

        try store.openExpedition(id: exp.id)
        store.selectGroup(id: store.groups.first?.id)
        XCTAssertNotNil(store.selectedGroupId)

        store.selectAllPhotosOverview()
        XCTAssertNil(store.selectedGroupId)
        XCTAssertEqual(store.activeFilter, .all)
        XCTAssertEqual(store.visibleAssets.count, 5)
    }
}
