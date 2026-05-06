import Foundation
import GRDB
import Testing

@testable import Luma

@Suite("ActionPanel Integration Tests")
struct ActionPanelIntegrationTests {

    @MainActor
    private func makeEnv() throws -> (LumaDatabase, ActionRunner) {
        let db = try LumaDatabase.inMemory()
        let runner = ActionRunner(
            db: db,
            actionJobRepo: GRDBActionJobRepository(dbQueue: db.dbQueue),
            archiveManifestRepo: GRDBArchiveManifestRepository(dbQueue: db.dbQueue),
            expeditionAssetRepo: GRDBExpeditionAssetRepository(dbQueue: db.dbQueue),
            assetRepo: GRDBMasterAssetRepository(dbQueue: db.dbQueue)
        )
        return (db, runner)
    }

    @Test("Submit exportToFolder creates pending job")
    @MainActor
    func testSubmitExportJob() throws {
        let (_, runner) = try makeEnv()
        let job = try runner.submit(
            kind: .exportToFolder,
            targetAssetIds: [UUID(), UUID(), UUID()]
        )

        #expect(job.kind == .exportToFolder)
        #expect(job.status == .pending)
        #expect(job.targetAssetIds.count == 3)
    }

    @Test("Submit syncAlbumToPhotos creates pending job with albumId")
    @MainActor
    func testSubmitSyncJob() async throws {
        let (db, runner) = try makeEnv()
        let albumId = UUID()
        let now = Date().timeIntervalSinceReferenceDate
        try await db.dbQueue.write { database in
            try AlbumRecord(
                id: albumId.uuidString,
                expeditionId: nil,
                name: "TestAlbum",
                kind: "manual",
                ruleJSON: nil,
                createdAt: now,
                updatedAt: now
            ).insert(database)
        }

        let job = try runner.submit(
            kind: .syncAlbumToPhotos,
            albumId: albumId
        )

        #expect(job.kind == .syncAlbumToPhotos)
        #expect(job.status == .pending)
        #expect(job.albumId == albumId)
    }

    @Test("ActionKind round-trip through ActionJob record")
    func testActionKindRoundTrip() {
        for kind in [ActionKind.exportToFolder, .syncAlbumToPhotos, .archiveVideo, .archiveLowres, .archiveMarkerOnly] {
            let record = ActionJobRecord(
                id: UUID().uuidString,
                expeditionId: nil,
                albumId: nil,
                kind: kind.rawValue,
                targetAssetIdsJSON: nil,
                status: "pending",
                createdAt: Date().timeIntervalSinceReferenceDate,
                completedAt: nil,
                resultURL: nil,
                errorMessage: nil
            )
            let job = ActionJob(record: record)
            #expect(job?.kind == kind)
        }
    }
}
