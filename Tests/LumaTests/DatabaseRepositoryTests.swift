import Foundation
import XCTest
import GRDB
@testable import Luma

final class DatabaseRepositoryTests: XCTestCase {

    // MARK: - Helpers

    func makeDB() throws -> LumaDatabase {
        try LumaDatabase.inMemory()
    }

    func makeAssetSource(id: String = UUID().uuidString) -> AssetSourceRecord {
        AssetSourceRecord(
            id: id, kind: "sdCard", displayName: "Test SD",
            rootIdentifier: "/Volumes/SD", isMutable: false,
            supportsDelete: false, supportsAlbumWrite: false,
            supportsOriginalAccess: true,
            createdAt: Date().timeIntervalSinceReferenceDate,
            updatedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    func makeMasterAsset(
        id: String = UUID().uuidString,
        sourceId: String,
        contentHash: String? = nil,
        externalIdentifier: String? = nil
    ) -> MasterAssetRecord {
        MasterAssetRecord(
            id: id, sourceId: sourceId, sourceKind: "sdCard",
            storageMode: "managed", externalIdentifier: externalIdentifier,
            originalURL: nil, localManagedURL: nil, previewURL: nil,
            rawURL: nil, livePhotoVideoURL: nil, thumbnailCacheURL: nil,
            previewCacheURL: nil, fingerprint: nil, contentHash: contentHash,
            baseName: "IMG_0001", mediaType: "photo",
            captureDate: Date().timeIntervalSinceReferenceDate,
            latitude: nil, longitude: nil, focalLength: nil,
            aperture: nil, shutterSpeed: nil, iso: nil,
            cameraModel: nil, lensModel: nil,
            imageWidth: nil, imageHeight: nil,
            createdAt: Date().timeIntervalSinceReferenceDate,
            updatedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    func makeExpedition(id: String = UUID().uuidString) -> ExpeditionRecord {
        ExpeditionRecord(
            id: id, name: "Test Expedition", subtitle: nil,
            description: nil, coverAssetId: nil,
            startDate: nil, endDate: nil,
            sourceMode: "sdCard", status: "reviewing",
            isMacPhotos: false,
            createdAt: Date().timeIntervalSinceReferenceDate,
            updatedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    func makeExpeditionAsset(
        id: String = UUID().uuidString,
        expeditionId: String,
        assetId: String,
        decision: String = "pending"
    ) -> ExpeditionAssetRecord {
        ExpeditionAssetRecord(
            id: id, expeditionId: expeditionId, assetId: assetId,
            addedAt: Date().timeIntervalSinceReferenceDate,
            addedBy: "test", localOrder: 0,
            decision: decision, rating: nil, colorLabel: nil,
            isRecommended: false, isBestInGroup: false,
            isUserOverride: false, isArchived: false,
            isHiddenInExpedition: false,
            updatedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    func makePhotoGroup(
        id: String = UUID().uuidString,
        expeditionId: String
    ) -> PhotoGroupRecord {
        PhotoGroupRecord(
            id: id, expeditionId: expeditionId,
            name: "Test Group", coverAssetId: nil,
            groupComment: nil, timeRangeStart: nil, timeRangeEnd: nil,
            latitude: nil, longitude: nil, reviewed: false,
            createdAt: Date().timeIntervalSinceReferenceDate,
            updatedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    func makeAssetScore(
        id: String = UUID().uuidString,
        assetId: String,
        timestamp: Double = Date().timeIntervalSinceReferenceDate
    ) -> AssetScoreRecord {
        AssetScoreRecord(
            id: id, assetId: assetId, provider: "test",
            composition: 80, exposure: 70, color: 90,
            sharpness: 85, story: 60, overall: 77,
            comment: nil, recommended: true,
            timestamp: timestamp
        )
    }

    func makeActionJob(
        id: String = UUID().uuidString,
        expeditionId: String? = nil,
        status: String = "pending"
    ) -> ActionJobRecord {
        ActionJobRecord(
            id: id, expeditionId: expeditionId, albumId: nil,
            kind: "export", targetAssetIdsJSON: nil,
            status: status,
            createdAt: Date().timeIntervalSinceReferenceDate,
            completedAt: nil, resultURL: nil, errorMessage: nil
        )
    }

    /// Insert an AssetSource directly, returning its id for FK use.
    @discardableResult
    func insertAssetSource(db: LumaDatabase, id: String = UUID().uuidString) throws -> String {
        let source = makeAssetSource(id: id)
        try db.dbQueue.write { tx in try source.insert(tx) }
        return id
    }

    /// Insert an AssetSource + MasterAsset, returning the asset id.
    @discardableResult
    func insertMasterAsset(
        db: LumaDatabase,
        assetId: String = UUID().uuidString,
        sourceId: String? = nil,
        contentHash: String? = nil,
        externalIdentifier: String? = nil
    ) throws -> String {
        let srcId = sourceId ?? UUID().uuidString
        try insertAssetSource(db: db, id: srcId)
        let asset = makeMasterAsset(
            id: assetId, sourceId: srcId,
            contentHash: contentHash, externalIdentifier: externalIdentifier
        )
        try db.dbQueue.write { tx in try asset.insert(tx) }
        return assetId
    }

    /// Insert an Expedition directly, returning its id.
    @discardableResult
    func insertExpedition(
        db: LumaDatabase,
        id: String = UUID().uuidString,
        isMacPhotos: Bool = false
    ) throws -> String {
        var exp = makeExpedition(id: id)
        exp.isMacPhotos = isMacPhotos
        try db.dbQueue.write { tx in try exp.insert(tx) }
        return id
    }

    // MARK: - 1. LumaDatabase Tests

    func testDatabaseCreation() throws {
        let db = try makeDB()
        XCTAssertNotNil(db)
    }

    func testAllTablesExist() throws {
        let db = try makeDB()
        let tables: [String] = try db.dbQueue.read { tx in
            try String.fetchAll(tx, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                ORDER BY name
            """)
        }
        let expected: Set<String> = [
            "action_jobs",
            "album_assets",
            "albums",
            "archive_manifests",
            "asset_scores",
            "asset_sources",
            "expedition_assets",
            "expedition_recommendations",
            "expeditions",
            "external_album_refs",
            "import_sessions",
            "master_assets",
            "photo_group_assets",
            "photo_groups",
            "photo_subgroup_assets",
            "photo_subgroups",
        ]
        XCTAssertEqual(Set(tables), expected, "Expected \(expected.count) tables, got \(tables.count): \(tables)")
    }

    // MARK: - 2. MasterAssetRepository Tests

    func testMasterAsset_InsertAndFetchById() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        let asset = makeMasterAsset(sourceId: sourceId, contentHash: "hash1")
        try repo.insert(asset)

        let fetched = try repo.fetchById(asset.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, asset.id)
        XCTAssertEqual(fetched?.baseName, "IMG_0001")
        XCTAssertEqual(fetched?.contentHash, "hash1")
        XCTAssertEqual(fetched?.sourceId, sourceId)
    }

    func testMasterAsset_FetchByContentHash() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        let asset = makeMasterAsset(sourceId: sourceId, contentHash: "abc123")
        try repo.insert(asset)

        let found = try repo.fetchByContentHash("abc123")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, asset.id)

        let notFound = try repo.fetchByContentHash("nonexistent")
        XCTAssertNil(notFound)
    }

    func testMasterAsset_FetchByExternalId() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        let asset = makeMasterAsset(sourceId: sourceId, externalIdentifier: "ph-123")
        try repo.insert(asset)

        let found = try repo.fetchByExternalId("ph-123")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, asset.id)

        let notFound = try repo.fetchByExternalId("ph-999")
        XCTAssertNil(notFound)
    }

    func testMasterAsset_FetchAll() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        for _ in 0..<3 {
            try repo.insert(makeMasterAsset(sourceId: sourceId))
        }

        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 3)
    }

    func testMasterAsset_FetchCount() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        try repo.insert(makeMasterAsset(sourceId: sourceId))
        try repo.insert(makeMasterAsset(sourceId: sourceId))

        XCTAssertEqual(try repo.fetchCount(), 2)
    }

    func testMasterAsset_Update() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        var asset = makeMasterAsset(sourceId: sourceId)
        try repo.insert(asset)

        asset.baseName = "IMG_9999"
        try repo.update(asset)

        let fetched = try repo.fetchById(asset.id)
        XCTAssertEqual(fetched?.baseName, "IMG_9999")
    }

    func testMasterAsset_Delete() throws {
        let db = try makeDB()
        let sourceId = try insertAssetSource(db: db)
        let repo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)

        let asset = makeMasterAsset(sourceId: sourceId)
        try repo.insert(asset)
        XCTAssertNotNil(try repo.fetchById(asset.id))

        try repo.delete(id: asset.id)
        XCTAssertNil(try repo.fetchById(asset.id))
    }

    // MARK: - 3. ExpeditionRepository Tests

    func testExpedition_CRUD() throws {
        let db = try makeDB()
        let repo = GRDBExpeditionRepository(dbQueue: db.dbQueue)

        var exp = makeExpedition()
        try repo.insert(exp)

        let fetched = try repo.fetchById(exp.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Test Expedition")

        exp.name = "Updated Expedition"
        try repo.update(exp)
        XCTAssertEqual(try repo.fetchById(exp.id)?.name, "Updated Expedition")

        try repo.delete(id: exp.id)
        XCTAssertNil(try repo.fetchById(exp.id))
    }

    func testExpedition_FetchNonMacPhotos() throws {
        let db = try makeDB()
        let repo = GRDBExpeditionRepository(dbQueue: db.dbQueue)

        var nonMac = makeExpedition()
        nonMac.isMacPhotos = false
        try repo.insert(nonMac)

        var mac = makeExpedition()
        mac.isMacPhotos = true
        try repo.insert(mac)

        let results = try repo.fetchNonMacPhotos()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, nonMac.id)
    }

    func testExpedition_FetchMacPhotos() throws {
        let db = try makeDB()
        let repo = GRDBExpeditionRepository(dbQueue: db.dbQueue)

        var nonMac = makeExpedition()
        nonMac.isMacPhotos = false
        try repo.insert(nonMac)

        var mac = makeExpedition()
        mac.isMacPhotos = true
        try repo.insert(mac)

        let results = try repo.fetchMacPhotos()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, mac.id)
    }

    // MARK: - 4. ExpeditionAssetRepository Tests

    func testExpeditionAsset_InsertAndFetch() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)

        let record = makeExpeditionAsset(expeditionId: expId, assetId: assetId)
        try repo.insert(record)

        let results = try repo.fetchByExpedition(expId)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.assetId, assetId)
    }

    func testExpeditionAsset_UniqueConstraint() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)

        let first = makeExpeditionAsset(expeditionId: expId, assetId: assetId)
        try repo.insert(first)

        let duplicate = makeExpeditionAsset(expeditionId: expId, assetId: assetId)
        XCTAssertThrowsError(try repo.insert(duplicate))
    }

    func testExpeditionAsset_Exists() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)

        XCTAssertFalse(try repo.exists(expeditionId: expId, assetId: assetId))

        let record = makeExpeditionAsset(expeditionId: expId, assetId: assetId)
        try repo.insert(record)

        XCTAssertTrue(try repo.exists(expeditionId: expId, assetId: assetId))
    }

    func testExpeditionAsset_SetDecision() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)

        let record = makeExpeditionAsset(expeditionId: expId, assetId: assetId, decision: "pending")
        try repo.insert(record)

        try repo.setDecision(id: record.id, decision: "picked")

        let results = try repo.fetchByExpedition(expId)
        XCTAssertEqual(results.first?.decision, "picked")
    }

    func testExpeditionAsset_FetchByExpeditionAndDecision() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId1 = try insertMasterAsset(db: db)
        let assetId2 = try insertMasterAsset(db: db)
        let repo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)

        try repo.insert(makeExpeditionAsset(expeditionId: expId, assetId: assetId1, decision: "pending"))
        try repo.insert(makeExpeditionAsset(expeditionId: expId, assetId: assetId2, decision: "picked"))

        let pending = try repo.fetchByExpeditionAndDecision(expId, decision: "pending")
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.assetId, assetId1)

        let picked = try repo.fetchByExpeditionAndDecision(expId, decision: "picked")
        XCTAssertEqual(picked.count, 1)
        XCTAssertEqual(picked.first?.assetId, assetId2)
    }

    // MARK: - 5. PhotoGroupRepository Tests

    func testPhotoGroup_InsertAndFetchByExpedition() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let repo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)

        let group = makePhotoGroup(expeditionId: expId)
        try repo.insert(group)

        let results = try repo.fetchByExpedition(expId)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, group.id)
        XCTAssertEqual(results.first?.name, "Test Group")
    }

    func testPhotoGroup_AddAndFetchAssets() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)

        let group = makePhotoGroup(expeditionId: expId)
        try repo.insert(group)

        let groupAsset = PhotoGroupAssetRecord(
            groupId: group.id, assetId: assetId, isRecommended: false
        )
        try repo.addAsset(groupAsset)

        let assets = try repo.fetchAssetsForGroup(group.id)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.assetId, assetId)
    }

    func testPhotoGroup_RemoveAsset() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)

        let group = makePhotoGroup(expeditionId: expId)
        try repo.insert(group)

        let groupAsset = PhotoGroupAssetRecord(
            groupId: group.id, assetId: assetId, isRecommended: false
        )
        try repo.addAsset(groupAsset)
        XCTAssertEqual(try repo.fetchAssetsForGroup(group.id).count, 1)

        try repo.removeAsset(groupId: group.id, assetId: assetId)
        XCTAssertEqual(try repo.fetchAssetsForGroup(group.id).count, 0)
    }

    // MARK: - 6. AssetScoreRepository Tests

    func testAssetScore_InsertAndFetchByAsset() throws {
        let db = try makeDB()
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBAssetScoreRepository(dbQueue: db.dbQueue)

        let score = makeAssetScore(assetId: assetId)
        try repo.insert(score)

        let results = try repo.fetchByAsset(assetId)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, score.id)
        XCTAssertEqual(results.first?.overall, 77)
    }

    func testAssetScore_FetchLatestByAsset() throws {
        let db = try makeDB()
        let assetId = try insertMasterAsset(db: db)
        let repo = GRDBAssetScoreRepository(dbQueue: db.dbQueue)

        let now = Date().timeIntervalSinceReferenceDate
        let older = makeAssetScore(assetId: assetId, timestamp: now - 100)
        let newer = makeAssetScore(assetId: assetId, timestamp: now)
        try repo.insert(older)
        try repo.insert(newer)

        let latest = try repo.fetchLatestByAsset(assetId)
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.id, newer.id)
    }

    // MARK: - 7. ActionJobRepository Tests

    func testActionJob_InsertAndFetchByExpedition() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let repo = GRDBActionJobRepository(dbQueue: db.dbQueue)

        let job = makeActionJob(expeditionId: expId, status: "pending")
        try repo.insert(job)

        let results = try repo.fetchByExpedition(expId)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, job.id)
        XCTAssertEqual(results.first?.kind, "export")
    }

    func testActionJob_FetchPending() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let repo = GRDBActionJobRepository(dbQueue: db.dbQueue)

        try repo.insert(makeActionJob(expeditionId: expId, status: "pending"))
        try repo.insert(makeActionJob(expeditionId: expId, status: "completed"))

        let pending = try repo.fetchPending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.status, "pending")
    }

    func testActionJob_FetchCompleted() throws {
        let db = try makeDB()
        let expId = try insertExpedition(db: db)
        let repo = GRDBActionJobRepository(dbQueue: db.dbQueue)

        try repo.insert(makeActionJob(expeditionId: expId, status: "pending"))
        try repo.insert(makeActionJob(expeditionId: expId, status: "completed"))

        let completed = try repo.fetchCompleted()
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.status, "completed")
    }
}
