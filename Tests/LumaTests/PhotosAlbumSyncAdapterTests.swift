import Foundation
import GRDB
import Testing

@testable import Luma

final class MockAlbumSyncAdapter: AlbumSyncAdapter, @unchecked Sendable {
    var displayName: String { "Mock Photos" }

    var createAlbumCallCount = 0
    var updateAlbumCallCount = 0
    var removeAssetsCallCount = 0
    var validateAccessResult = true
    var lastCreatedName: String?
    var lastCreatedAssets: [MasterAsset] = []
    var lastUpdatedRef: ExternalAlbumRef?
    var lastUpdatedAssets: [MasterAsset] = []
    var lastRemovedAssets: [MasterAsset] = []
    var lastRemovedRef: ExternalAlbumRef?
    var shouldThrow = false

    func createAlbum(name: String, assets: [MasterAsset]) async throws -> ExternalAlbumRef {
        if shouldThrow { throw LumaError.persistenceFailed("Mock error") }
        createAlbumCallCount += 1
        lastCreatedName = name
        lastCreatedAssets = assets
        let record = ExternalAlbumRefRecord(
            albumId: UUID().uuidString,
            provider: ExternalAlbumProvider.macPhotos.rawValue,
            localIdentifier: "mock-\(UUID().uuidString.prefix(8))"
        )
        return ExternalAlbumRef(record: record)!
    }

    func updateAlbum(_ ref: ExternalAlbumRef, assets: [MasterAsset]) async throws {
        if shouldThrow { throw LumaError.persistenceFailed("Mock error") }
        updateAlbumCallCount += 1
        lastUpdatedRef = ref
        lastUpdatedAssets = assets
    }

    func removeAssets(_ assets: [MasterAsset], from ref: ExternalAlbumRef) async throws {
        if shouldThrow { throw LumaError.persistenceFailed("Mock error") }
        removeAssetsCallCount += 1
        lastRemovedAssets = assets
        lastRemovedRef = ref
    }

    func validateAccess(_ ref: ExternalAlbumRef) async throws -> Bool {
        return validateAccessResult
    }
}

@Suite("PhotosAlbumSyncAdapter Tests")
struct PhotosAlbumSyncAdapterTests {

    private func makeEnv() throws -> (LumaDatabase, AlbumManager) {
        let db = try LumaDatabase.inMemory()
        let repo = GRDBAlbumRepository(dbQueue: db.dbQueue)
        let mgr = AlbumManager(db: db, albumRepo: repo)
        return (db, mgr)
    }

    @Test("MockAlbumSyncAdapter createAlbum returns valid ref")
    func testMockCreateAlbum() async throws {
        let adapter = MockAlbumSyncAdapter()
        let ref = try await adapter.createAlbum(name: "Test Album", assets: [])
        #expect(ref.provider == .macPhotos)
        #expect(!ref.localIdentifier.isEmpty)
        #expect(adapter.createAlbumCallCount == 1)
        #expect(adapter.lastCreatedName == "Test Album")
    }

    @Test("MockAlbumSyncAdapter updateAlbum tracks calls")
    func testMockUpdateAlbum() async throws {
        let adapter = MockAlbumSyncAdapter()
        let refRecord = ExternalAlbumRefRecord(
            albumId: UUID().uuidString,
            provider: "macPhotos",
            localIdentifier: "test-id"
        )
        let ref = ExternalAlbumRef(record: refRecord)!

        try await adapter.updateAlbum(ref, assets: [])
        #expect(adapter.updateAlbumCallCount == 1)
        #expect(adapter.lastUpdatedRef?.localIdentifier == "test-id")
    }

    @Test("AlbumManager markAlbumAsSynced converts to photosBacked")
    func testMarkAlbumAsSynced() throws {
        let (_, mgr) = try makeEnv()

        let album = try mgr.createManualAlbum(name: "Local Album")
        #expect(album.kind == .manual)

        let refRecord = ExternalAlbumRefRecord(
            albumId: album.id.uuidString,
            provider: "macPhotos",
            localIdentifier: "photos-123"
        )
        let ref = ExternalAlbumRef(record: refRecord)!

        try mgr.markAlbumAsSynced(albumId: album.id, ref: ref)

        let updated = try mgr.fetchAlbum(id: album.id)
        #expect(updated?.kind == .photosBacked)

        let fetchedRef = try mgr.fetchExternalRef(albumId: album.id)
        #expect(fetchedRef?.localIdentifier == "photos-123")
    }

    @Test("AlbumManager convertToLocalAlbum removes ref and resets kind")
    func testConvertToLocalAlbum() throws {
        let (_, mgr) = try makeEnv()

        let album = try mgr.createManualAlbum(name: "Synced Album")
        let refRecord = ExternalAlbumRefRecord(
            albumId: album.id.uuidString,
            provider: "macPhotos",
            localIdentifier: "photos-456"
        )
        let ref = ExternalAlbumRef(record: refRecord)!
        try mgr.markAlbumAsSynced(albumId: album.id, ref: ref)

        let beforeConvert = try mgr.fetchAlbum(id: album.id)
        #expect(beforeConvert?.kind == .photosBacked)

        try mgr.convertToLocalAlbum(albumId: album.id)

        let afterConvert = try mgr.fetchAlbum(id: album.id)
        #expect(afterConvert?.kind == .manual)
        #expect(try mgr.fetchExternalRef(albumId: album.id) == nil)
    }

    @Test("AlbumManager validateAlbumRef delegates to adapter")
    func testValidateAlbumRef() async throws {
        let (_, mgr) = try makeEnv()
        let adapter = MockAlbumSyncAdapter()

        let album = try mgr.createManualAlbum(name: "Check Album")
        let refRecord = ExternalAlbumRefRecord(
            albumId: album.id.uuidString,
            provider: "macPhotos",
            localIdentifier: "photos-789"
        )
        let ref = ExternalAlbumRef(record: refRecord)!
        try mgr.saveExternalRef(ref)

        adapter.validateAccessResult = true
        let isValid = try await mgr.validateAlbumRef(albumId: album.id, adapter: adapter)
        #expect(isValid == true)

        adapter.validateAccessResult = false
        let isInvalid = try await mgr.validateAlbumRef(albumId: album.id, adapter: adapter)
        #expect(isInvalid == false)
    }

    @Test("MockAlbumSyncAdapter error propagation")
    func testSyncErrorPropagation() async throws {
        let adapter = MockAlbumSyncAdapter()
        adapter.shouldThrow = true

        do {
            _ = try await adapter.createAlbum(name: "Fail", assets: [])
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is LumaError)
        }
    }
}
