import Foundation
import GRDB
import Testing

@testable import Luma

@Suite("AlbumManager Tests")
struct AlbumManagerTests {

    private func makeEnv() throws -> (LumaDatabase, AlbumManager) {
        let db = try LumaDatabase.inMemory()
        let repo = GRDBAlbumRepository(dbQueue: db.dbQueue)
        let mgr = AlbumManager(db: db, albumRepo: repo)
        return (db, mgr)
    }

    @Test("Create manual album")
    func testCreateManualAlbum() throws {
        let (_, mgr) = try makeEnv()

        let album = try mgr.createManualAlbum(name: "京都精选")
        #expect(album.name == "京都精选")
        #expect(album.kind == .manual)
        #expect(album.expeditionId == nil)
        #expect(album.rule == nil)

        let all = try mgr.fetchAllAlbums()
        #expect(all.count == 1)
    }

    @Test("Create manual album with expedition")
    func testCreateManualAlbumWithExpedition() throws {
        let (db, mgr) = try makeEnv()

        let expId = UUID()
        let now = Date().timeIntervalSinceReferenceDate
        try db.dbQueue.write { db in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Test Expedition",
                subtitle: nil,
                description: nil,
                coverAssetId: nil,
                startDate: nil,
                endDate: nil,
                sourceMode: "sdCard",
                status: "reviewing",
                isMacPhotos: false,
                createdAt: now,
                updatedAt: now
            ).insert(db)
        }

        let album = try mgr.createManualAlbum(name: "旅途精选", expeditionId: expId)
        #expect(album.expeditionId == expId)

        let expAlbums = try mgr.fetchAlbumsForExpedition(expId)
        #expect(expAlbums.count == 1)
    }

    @Test("Delete album")
    func testDeleteAlbum() throws {
        let (_, mgr) = try makeEnv()

        let album = try mgr.createManualAlbum(name: "To Delete")
        #expect(try mgr.fetchAllAlbums().count == 1)

        try mgr.deleteAlbum(id: album.id)
        #expect(try mgr.fetchAllAlbums().count == 0)
    }

    @Test("Add and remove assets from album")
    func testAddRemoveAssets() throws {
        let (db, mgr) = try makeEnv()

        let album = try mgr.createManualAlbum(name: "Test Album")

        let assetId1 = UUID()
        let assetId2 = UUID()
        insertDummyAsset(db: db, id: assetId1)
        insertDummyAsset(db: db, id: assetId2)

        try mgr.addAssets(albumId: album.id, assetIds: [assetId1, assetId2])
        #expect(try mgr.fetchAssetCount(albumId: album.id) == 2)

        let assetIds = try mgr.fetchAlbumAssetIds(albumId: album.id)
        #expect(assetIds.count == 2)
        #expect(assetIds.contains(assetId1))
        #expect(assetIds.contains(assetId2))

        try mgr.removeAssets(albumId: album.id, assetIds: [assetId1])
        #expect(try mgr.fetchAssetCount(albumId: album.id) == 1)
    }

    @Test("Create smart album and evaluate picked rule")
    func testSmartAlbumPicked() throws {
        let (db, mgr) = try makeEnv()

        let expId = UUID()
        let now = Date().timeIntervalSinceReferenceDate
        try db.dbQueue.write { db in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Exp",
                subtitle: nil, description: nil, coverAssetId: nil,
                startDate: nil, endDate: nil,
                sourceMode: "sdCard", status: "reviewing",
                isMacPhotos: false,
                createdAt: now, updatedAt: now
            ).insert(db)
        }

        let pickedId = UUID()
        let rejectedId = UUID()
        let pendingId = UUID()
        insertDummyAsset(db: db, id: pickedId)
        insertDummyAsset(db: db, id: rejectedId)
        insertDummyAsset(db: db, id: pendingId)
        insertExpeditionAsset(db: db, expeditionId: expId, assetId: pickedId, decision: "picked")
        insertExpeditionAsset(db: db, expeditionId: expId, assetId: rejectedId, decision: "rejected")
        insertExpeditionAsset(db: db, expeditionId: expId, assetId: pendingId, decision: "pending")

        let rule = SmartAlbumRule(scope: .expedition(expId), filters: [.allPicked])
        let album = try mgr.createSmartAlbum(name: "已选", expeditionId: expId, rule: rule)
        #expect(album.kind == .smart)
        #expect(album.rule != nil)

        let result = try mgr.evaluateSmartRule(rule)
        #expect(result.count == 1)
        #expect(result.contains(pickedId))
    }

    @Test("Evaluate archived filter")
    func testArchivedFilter() throws {
        let (db, mgr) = try makeEnv()

        let expId = UUID()
        let now = Date().timeIntervalSinceReferenceDate
        try db.dbQueue.write { db in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Exp",
                subtitle: nil, description: nil, coverAssetId: nil,
                startDate: nil, endDate: nil,
                sourceMode: "sdCard", status: "reviewing",
                isMacPhotos: false,
                createdAt: now, updatedAt: now
            ).insert(db)
        }

        let archivedId = UUID()
        let normalId = UUID()
        insertDummyAsset(db: db, id: archivedId)
        insertDummyAsset(db: db, id: normalId)
        insertExpeditionAsset(db: db, expeditionId: expId, assetId: archivedId, decision: "rejected", isArchived: true)
        insertExpeditionAsset(db: db, expeditionId: expId, assetId: normalId, decision: "picked")

        let rule = SmartAlbumRule(scope: .expedition(expId), filters: [.archived])
        let result = try mgr.evaluateSmartRule(rule)
        #expect(result.count == 1)
        #expect(result.contains(archivedId))
    }

    @Test("External album ref lifecycle")
    func testExternalAlbumRef() throws {
        let (_, mgr) = try makeEnv()

        let album = try mgr.createManualAlbum(name: "Photos Album")
        let refRecord = ExternalAlbumRefRecord(
            albumId: album.id.uuidString,
            provider: ExternalAlbumProvider.macPhotos.rawValue,
            localIdentifier: "ABC-123"
        )
        let ref = ExternalAlbumRef(record: refRecord)!

        try mgr.saveExternalRef(ref)
        let fetched = try mgr.fetchExternalRef(albumId: album.id)
        #expect(fetched != nil)
        #expect(fetched?.localIdentifier == "ABC-123")
        #expect(fetched?.provider == .macPhotos)

        try mgr.deleteExternalRef(albumId: album.id)
        #expect(try mgr.fetchExternalRef(albumId: album.id) == nil)
    }

    // MARK: - Helpers

    private func insertDummyAsset(db: LumaDatabase, id: UUID) {
        let now = Date().timeIntervalSinceReferenceDate
        try? db.dbQueue.write { database in
            try MasterAssetRecord(
                id: id.uuidString,
                sourceId: nil,
                sourceKind: "sdCard",
                storageMode: "managed",
                externalIdentifier: nil,
                originalURL: nil,
                localManagedURL: nil,
                previewURL: nil,
                rawURL: nil,
                livePhotoVideoURL: nil,
                thumbnailCacheURL: nil,
                previewCacheURL: nil,
                fingerprint: nil,
                contentHash: nil,
                baseName: "test_\(id.uuidString.prefix(8))",
                mediaType: "photo",
                captureDate: now,
                latitude: nil,
                longitude: nil,
                focalLength: nil,
                aperture: nil,
                shutterSpeed: nil,
                iso: nil,
                cameraModel: nil,
                lensModel: nil,
                imageWidth: nil,
                imageHeight: nil,
                createdAt: now,
                updatedAt: now
            ).insert(database)
        }
    }

    private func insertExpeditionAsset(
        db: LumaDatabase,
        expeditionId: UUID,
        assetId: UUID,
        decision: String,
        isArchived: Bool = false
    ) {
        let now = Date().timeIntervalSinceReferenceDate
        try? db.dbQueue.write { database in
            try ExpeditionAssetRecord(
                id: UUID().uuidString,
                expeditionId: expeditionId.uuidString,
                assetId: assetId.uuidString,
                addedAt: now,
                addedBy: "sdImport",
                localOrder: 0,
                decision: decision,
                rating: nil,
                colorLabel: nil,
                isRecommended: false,
                isBestInGroup: false,
                isUserOverride: false,
                isArchived: isArchived,
                isHiddenInExpedition: false,
                updatedAt: now
            ).insert(database)
        }
    }
}
