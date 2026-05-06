import XCTest
import GRDB
@testable import Luma

final class BusinessManagerTests: XCTestCase {

    // MARK: - Helper

    private func makeTestEnvironment() throws -> (LumaDatabase, ExpeditionManager, AssetManager, AssetSourceManager) {
        let db = try LumaDatabase.inMemory()
        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
        let assetRepo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)
        let expAssetRepo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)
        let expMgr = ExpeditionManager(repo: expRepo)
        let assetMgr = AssetManager(db: db, assetRepo: assetRepo, expeditionAssetRepo: expAssetRepo)
        let sourceMgr = AssetSourceManager(db: db)
        return (db, expMgr, assetMgr, sourceMgr)
    }

    private func makeSourceAndAsset(
        sourceMgr: AssetSourceManager,
        assetMgr: AssetManager,
        baseName: String = "IMG_001",
        contentHash: String? = "hash123",
        externalIdentifier: String? = nil,
        originalURL: URL? = nil
    ) throws -> (AssetSource, MasterAsset) {
        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "Test", rootIdentifier: "/test")
        let asset = try assetMgr.createOrReuseMasterAsset(
            baseName: baseName, mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: externalIdentifier,
            contentHash: contentHash, originalURL: originalURL, metadata: nil
        )
        return (source, asset)
    }

    // MARK: - ExpeditionManager Tests

    func testCreateExpedition() throws {
        let (_, expMgr, _, _) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Trip", sourceMode: .sdCard)

        XCTAssertEqual(exp.name, "Trip")
        XCTAssertEqual(exp.status, .reviewing)
        XCTAssertEqual(exp.sourceMode, .sdCard)
    }

    func testUpdateExpedition() throws {
        let (_, expMgr, _, _) = try makeTestEnvironment()

        var exp = try expMgr.createExpedition(name: "Original", sourceMode: .localFolder)
        exp.name = "Updated"
        try expMgr.updateExpedition(exp)

        let fetched = try XCTUnwrap(expMgr.fetchExpedition(id: exp.id))
        XCTAssertEqual(fetched.name, "Updated")
    }

    func testDeleteExpedition() throws {
        let (_, expMgr, _, _) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "ToDelete", sourceMode: .sdCard)
        try expMgr.deleteExpedition(exp.id)

        XCTAssertNil(try expMgr.fetchExpedition(id: exp.id))
    }

    func testListExpeditions() throws {
        let (_, expMgr, _, _) = try makeTestEnvironment()

        _ = try expMgr.createExpedition(name: "A", sourceMode: .sdCard)
        _ = try expMgr.createExpedition(name: "B", sourceMode: .localFolder)
        _ = try expMgr.createExpedition(name: "C", sourceMode: .mixed)

        let list = try expMgr.listExpeditions()
        XCTAssertEqual(list.count, 3)
    }

    func testSetExpeditionCover() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Cover", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)

        try expMgr.setExpeditionCover(expeditionId: exp.id, assetId: asset.id)

        let fetched = try XCTUnwrap(expMgr.fetchExpedition(id: exp.id))
        XCTAssertEqual(fetched.coverAssetId, asset.id)
    }

    func testUpdateExpeditionStatus() throws {
        let (_, expMgr, _, _) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Status", sourceMode: .sdCard)
        XCTAssertEqual(exp.status, .reviewing)

        try expMgr.updateExpeditionStatus(expeditionId: exp.id, status: .completed)

        let fetched = try XCTUnwrap(expMgr.fetchExpedition(id: exp.id))
        XCTAssertEqual(fetched.status, .completed)
    }

    func testDeleteExpeditionCascadesExpeditionAsset() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Cascade", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)
        _ = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )

        XCTAssertNotNil(try assetMgr.fetchExpeditionAsset(expeditionId: exp.id, assetId: asset.id))

        try expMgr.deleteExpedition(exp.id)

        let cascaded = try assetMgr.fetchExpeditionAsset(expeditionId: exp.id, assetId: asset.id)
        XCTAssertNil(cascaded, "ExpeditionAsset should be cascade-deleted when expedition is removed")

        let masterAssets = try assetMgr.fetchAllMasterAssets()
        XCTAssertTrue(
            masterAssets.contains(where: { $0.id == asset.id }),
            "MasterAsset must survive expedition deletion"
        )
    }

    // MARK: - AssetManager Tests

    func testCreateNewMasterAsset() throws {
        let (_, _, assetMgr, sourceMgr) = try makeTestEnvironment()

        let (_, asset) = try makeSourceAndAsset(
            sourceMgr: sourceMgr, assetMgr: assetMgr,
            baseName: "IMG_NEW", contentHash: "unique_hash"
        )

        XCTAssertEqual(asset.baseName, "IMG_NEW")
        XCTAssertEqual(asset.mediaType, .photo)
        XCTAssertEqual(asset.contentHash, "unique_hash")
    }

    func testDedupByContentHash() throws {
        let (_, _, assetMgr, sourceMgr) = try makeTestEnvironment()

        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "S", rootIdentifier: "/s")
        let first = try assetMgr.createOrReuseMasterAsset(
            baseName: "A", mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: "abc", originalURL: nil, metadata: nil
        )
        let second = try assetMgr.createOrReuseMasterAsset(
            baseName: "B", mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: "abc", originalURL: nil, metadata: nil
        )

        XCTAssertEqual(first.id, second.id, "Same contentHash should dedup to the same asset")
    }

    func testDedupByExternalId() throws {
        let (_, _, assetMgr, sourceMgr) = try makeTestEnvironment()

        let source = try sourceMgr.registerSource(kind: .macPhotos, displayName: "Photos", rootIdentifier: nil)
        let first = try assetMgr.createOrReuseMasterAsset(
            baseName: "P1", mediaType: .photo,
            sourceKind: .macPhotos, storageMode: .externalReference,
            sourceId: source.id, externalIdentifier: "ph-1",
            contentHash: nil, originalURL: nil, metadata: nil
        )
        let second = try assetMgr.createOrReuseMasterAsset(
            baseName: "P2", mediaType: .photo,
            sourceKind: .macPhotos, storageMode: .externalReference,
            sourceId: source.id, externalIdentifier: "ph-1",
            contentHash: nil, originalURL: nil, metadata: nil
        )

        XCTAssertEqual(first.id, second.id, "Same externalIdentifier should dedup to the same asset")
    }

    func testDedupByOriginalURL() throws {
        let (_, _, assetMgr, sourceMgr) = try makeTestEnvironment()

        let source = try sourceMgr.registerSource(kind: .localFolder, displayName: "Folder", rootIdentifier: "/photos")
        let url = URL(fileURLWithPath: "/photos/IMG_001.jpg")
        let first = try assetMgr.createOrReuseMasterAsset(
            baseName: "IMG_001", mediaType: .photo,
            sourceKind: .localFolder, storageMode: .referenced,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: nil, originalURL: url, metadata: nil
        )
        let second = try assetMgr.createOrReuseMasterAsset(
            baseName: "IMG_001_copy", mediaType: .photo,
            sourceKind: .localFolder, storageMode: .referenced,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: nil, originalURL: url, metadata: nil
        )

        XCTAssertEqual(first.id, second.id, "Same originalURL should dedup to the same asset")
    }

    func testAddAssetToExpedition() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Exp", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)

        let ea = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )

        XCTAssertEqual(ea.expeditionId, exp.id)
        XCTAssertEqual(ea.assetId, asset.id)

        let fetched = try assetMgr.fetchExpeditionAsset(expeditionId: exp.id, assetId: asset.id)
        XCTAssertNotNil(fetched)
    }

    func testAddAssetToExpeditionIdempotent() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Idem", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)

        let first = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )
        let second = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )

        XCTAssertEqual(first.id, second.id, "Adding the same asset twice should return the same ExpeditionAsset")
    }

    func testRemoveAssetFromExpedition() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Rem", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)
        _ = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )

        try assetMgr.removeAssetFromExpedition(assetId: asset.id, expeditionId: exp.id)

        XCTAssertNil(try assetMgr.fetchExpeditionAsset(expeditionId: exp.id, assetId: asset.id))
    }

    func testSetDecision() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Dec", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)
        _ = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )

        try assetMgr.setDecision(expeditionId: exp.id, assetId: asset.id, decision: .picked)

        let ea = try XCTUnwrap(assetMgr.fetchExpeditionAsset(expeditionId: exp.id, assetId: asset.id))
        XCTAssertEqual(ea.decision, .picked)
    }

    func testSetRating() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Rate", sourceMode: .sdCard)
        let (_, asset) = try makeSourceAndAsset(sourceMgr: sourceMgr, assetMgr: assetMgr)
        _ = try assetMgr.addAssetToExpedition(
            assetId: asset.id, expeditionId: exp.id, addedBy: .manualAdd
        )

        try assetMgr.setRating(expeditionId: exp.id, assetId: asset.id, rating: 4)

        let ea = try XCTUnwrap(assetMgr.fetchExpeditionAsset(expeditionId: exp.id, assetId: asset.id))
        XCTAssertEqual(ea.rating, 4)
    }

    func testFetchAssetsForExpedition() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Fetch", sourceMode: .sdCard)
        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "S", rootIdentifier: "/s")
        let a1 = try assetMgr.createOrReuseMasterAsset(
            baseName: "A", mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: "h1", originalURL: nil, metadata: nil
        )
        let a2 = try assetMgr.createOrReuseMasterAsset(
            baseName: "B", mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: "h2", originalURL: nil, metadata: nil
        )
        _ = try assetMgr.addAssetToExpedition(assetId: a1.id, expeditionId: exp.id, addedBy: .manualAdd)
        _ = try assetMgr.addAssetToExpedition(assetId: a2.id, expeditionId: exp.id, addedBy: .manualAdd)

        let results = try assetMgr.fetchAssetsForExpedition(expeditionId: exp.id)
        XCTAssertEqual(results.count, 2)
    }

    func testFetchAssetsForExpeditionByDecision() throws {
        let (_, expMgr, assetMgr, sourceMgr) = try makeTestEnvironment()

        let exp = try expMgr.createExpedition(name: "Filter", sourceMode: .sdCard)
        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "S", rootIdentifier: "/s")
        let a1 = try assetMgr.createOrReuseMasterAsset(
            baseName: "Keep", mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: "k1", originalURL: nil, metadata: nil
        )
        let a2 = try assetMgr.createOrReuseMasterAsset(
            baseName: "Drop", mediaType: .photo,
            sourceKind: .sdCard, storageMode: .managed,
            sourceId: source.id, externalIdentifier: nil,
            contentHash: "k2", originalURL: nil, metadata: nil
        )
        _ = try assetMgr.addAssetToExpedition(assetId: a1.id, expeditionId: exp.id, addedBy: .manualAdd)
        _ = try assetMgr.addAssetToExpedition(assetId: a2.id, expeditionId: exp.id, addedBy: .manualAdd)

        try assetMgr.setDecision(expeditionId: exp.id, assetId: a1.id, decision: .picked)
        try assetMgr.setDecision(expeditionId: exp.id, assetId: a2.id, decision: .rejected)

        let picked = try assetMgr.fetchAssetsForExpedition(expeditionId: exp.id, decision: .picked)
        XCTAssertEqual(picked.count, 1)
        XCTAssertEqual(picked.first?.id, a1.id)

        let rejected = try assetMgr.fetchAssetsForExpedition(expeditionId: exp.id, decision: .rejected)
        XCTAssertEqual(rejected.count, 1)
        XCTAssertEqual(rejected.first?.id, a2.id)
    }

    // MARK: - AssetSourceManager Tests

    func testRegisterSource() throws {
        let (_, _, _, sourceMgr) = try makeTestEnvironment()

        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "SD", rootIdentifier: "/vol/sd")

        XCTAssertEqual(source.kind, .sdCard)
        XCTAssertEqual(source.displayName, "SD")
        XCTAssertEqual(source.rootIdentifier, "/vol/sd")
        XCTAssertFalse(source.isMutable)
        XCTAssertTrue(source.supportsOriginalAccess)
    }

    func testListSources() throws {
        let (_, _, _, sourceMgr) = try makeTestEnvironment()

        _ = try sourceMgr.registerSource(kind: .sdCard, displayName: "SD1", rootIdentifier: "/a")
        _ = try sourceMgr.registerSource(kind: .localFolder, displayName: "Folder1", rootIdentifier: "/b")

        let list = try sourceMgr.listSources()
        XCTAssertEqual(list.count, 2)
    }

    func testDeleteSource() throws {
        let (_, _, _, sourceMgr) = try makeTestEnvironment()

        let source = try sourceMgr.registerSource(kind: .sdCard, displayName: "Gone", rootIdentifier: "/tmp")
        try sourceMgr.deleteSource(id: source.id)

        XCTAssertNil(try sourceMgr.fetchSource(id: source.id))
    }
}
