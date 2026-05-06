import Foundation
import Testing

@testable import Luma

final class MockPhotoLibraryProvider: PhotoLibraryProvider, @unchecked Sendable {
    var statusToReturn: PhotoAuthorizationStatus = .notDetermined
    var statusAfterRequest: PhotoAuthorizationStatus = .authorized
    var assetsToReturn: [PHAssetSnapshot] = []
    var collectionsToReturn: [PHCollectionSnapshot] = []
    var collectionAssetsToReturn: [String: [String]] = [:]

    func currentAuthorizationStatus() -> PhotoAuthorizationStatus { statusToReturn }

    func requestAuthorization() async -> PhotoAuthorizationStatus {
        statusToReturn = statusAfterRequest
        return statusAfterRequest
    }

    func enumerateAssets() async -> [PHAssetSnapshot] { assetsToReturn }

    func fetchCollections() async -> [PHCollectionSnapshot] { collectionsToReturn }

    func assetIdentifiers(in collectionId: String) async -> [String] {
        collectionAssetsToReturn[collectionId] ?? []
    }
}

@MainActor
private func makeTestEnv(
    provider: MockPhotoLibraryProvider = MockPhotoLibraryProvider()
) throws -> (LumaDatabase, MacPhotosManager, AssetManager, AssetSourceManager) {
    UserDefaults.standard.removeObject(forKey: "Luma.macPhotos.isDisconnectedByUser")
    let db = try LumaDatabase.inMemory()
    let assetRepo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)
    let expAssetRepo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)
    let assetManager = AssetManager(db: db, assetRepo: assetRepo, expeditionAssetRepo: expAssetRepo)
    let sourceManager = AssetSourceManager(db: db)
    let manager = MacPhotosManager(
        provider: provider,
        assetManager: assetManager,
        assetSourceManager: sourceManager,
        db: db
    )
    return (db, manager, assetManager, sourceManager)
}

private func makeSampleSnapshots(count: Int) -> [PHAssetSnapshot] {
    (0..<count).map { i -> PHAssetSnapshot in
        let date = Date(timeIntervalSinceReferenceDate: Double(i) * 86400)
        return PHAssetSnapshot(
            localIdentifier: "photo-\(i)",
            mediaType: .photo,
            pixelWidth: 4000,
            pixelHeight: 3000,
            creationDate: date,
            modificationDate: nil,
            latitude: i % 2 == 0 ? 35.6 : nil,
            longitude: i % 2 == 0 ? 139.7 : nil,
            isFavorite: i == 0,
            isLocallyAvailable: true
        )
    }
}

private func dbCount(_ db: LumaDatabase) throws -> Int {
    try db.dbQueue.read { db in try MasterAssetRecord.fetchCount(db) }
}

private func dbFirst(_ db: LumaDatabase) throws -> MasterAssetRecord? {
    try db.dbQueue.read { db in try MasterAssetRecord.fetchOne(db) }
}

@Suite("MacPhotosManager")
struct MacPhotosManagerTests {

    @Test("connect succeeds with authorized status")
    @MainActor
    func testConnectAuthorized() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = makeSampleSnapshots(count: 3)
        let (_, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        #expect(manager.isConnected)
        #expect(manager.totalIndexedCount == 3)
        #expect(manager.lastSyncDate != nil)
    }

    @Test("connect fails with denied status")
    @MainActor
    func testConnectDenied() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .denied
        let (_, manager, _, _) = try makeTestEnv(provider: provider)

        do {
            try await manager.connect()
            Issue.record("Should have thrown")
        } catch {
            #expect(!manager.isConnected)
        }
    }

    @Test("index deduplicates by externalIdentifier")
    @MainActor
    func testDeduplication() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        let snap = makeSampleSnapshots(count: 1)
        provider.assetsToReturn = snap + snap
        let (db, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        #expect(manager.totalIndexedCount == 2)
        #expect(try dbCount(db) == 1)
    }

    @Test("index writes correct storageMode and sourceKind")
    @MainActor
    func testAssetProperties() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = makeSampleSnapshots(count: 1)
        let (db, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        let record = try dbFirst(db)
        #expect(record != nil)
        #expect(record?.sourceKind == "macPhotos")
        #expect(record?.storageMode == "externalReference")
        #expect(record?.externalIdentifier == "photo-0")
    }

    @Test("index preserves GPS metadata")
    @MainActor
    func testGPSMetadata() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = makeSampleSnapshots(count: 1)
        let (db, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        let record = try dbFirst(db)
        #expect(record?.latitude != nil)
        #expect(record?.longitude != nil)
        #expect(record?.imageWidth == 4000)
        #expect(record?.imageHeight == 3000)
    }

    @Test("registers MacPhotos AssetSource")
    @MainActor
    func testAssetSourceCreation() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = []
        let (_, manager, _, sourceManager) = try makeTestEnv(provider: provider)

        try await manager.connect()
        let source = try sourceManager.fetchByKind(.macPhotos)
        #expect(source != nil)
        #expect(source?.kind == .macPhotos)
    }

    @Test("disconnect resets state but retains data")
    @MainActor
    func testDisconnect() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = makeSampleSnapshots(count: 2)
        let (db, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        #expect(manager.isConnected)
        manager.disconnect()
        #expect(!manager.isConnected)
        #expect(try dbCount(db) == 2)
    }

    @Test("refreshIndex re-indexes without duplication")
    @MainActor
    func testRefreshIndex() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = makeSampleSnapshots(count: 3)
        let (db, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        await manager.refreshIndex()
        #expect(try dbCount(db) == 3)
    }

    @Test("fetchCollections delegates to provider")
    @MainActor
    func testFetchCollections() async throws {
        let provider = MockPhotoLibraryProvider()
        provider.statusAfterRequest = .authorized
        provider.assetsToReturn = []
        provider.collectionsToReturn = [
            PHCollectionSnapshot(localIdentifier: "album-1", title: "Favorites", estimatedAssetCount: 10, collectionType: .smartAlbum),
            PHCollectionSnapshot(localIdentifier: "album-2", title: "My Trip", estimatedAssetCount: 50, collectionType: .userAlbum)
        ]
        let (_, manager, _, _) = try makeTestEnv(provider: provider)

        try await manager.connect()
        let collections = await manager.fetchCollections()
        #expect(collections.count == 2)
        #expect(collections[0].title == "Favorites")
    }
}
