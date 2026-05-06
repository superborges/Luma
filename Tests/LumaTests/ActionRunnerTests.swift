import Foundation
import GRDB
import Testing

@testable import Luma

@Suite("ActionRunner Tests")
struct ActionRunnerTests {

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

    @Test("Submit creates pending job")
    @MainActor
    func testSubmitCreatesPendingJob() async throws {
        let (db, runner) = try makeEnv()

        let expId = UUID()
        let now = Date().timeIntervalSinceReferenceDate
        try await db.dbQueue.write { database in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Exp", subtitle: nil, description: nil,
                coverAssetId: nil, startDate: nil, endDate: nil,
                sourceMode: "sdCard", status: "reviewing",
                isMacPhotos: false, createdAt: now, updatedAt: now
            ).insert(database)
        }

        let assetIds = [UUID(), UUID()]
        let job = try runner.submit(
            kind: .archiveVideo,
            expeditionId: expId,
            targetAssetIds: assetIds
        )

        #expect(job.kind == .archiveVideo)
        #expect(job.status == .pending)
        #expect(job.targetAssetIds.count == 2)
    }

    @Test("Cancel sets status to cancelled")
    @MainActor
    func testCancelJob() throws {
        let (_, runner) = try makeEnv()

        let job = try runner.submit(kind: .archiveMarkerOnly, targetAssetIds: [UUID()])
        #expect(job.status == .pending)

        try runner.cancel(jobId: job.id)

        let jobs = try runner.fetchActiveJobs()
        #expect(jobs.isEmpty)
    }

    @Test("Fetch active and completed jobs")
    @MainActor
    func testFetchActiveAndCompleted() throws {
        let (db, runner) = try makeEnv()

        _ = try runner.submit(kind: .archiveVideo, targetAssetIds: [UUID()])
        let now = Date().timeIntervalSinceReferenceDate
        try db.dbQueue.write { database in
            try ActionJobRecord(
                id: UUID().uuidString,
                expeditionId: nil, albumId: nil,
                kind: "archiveVideo",
                targetAssetIdsJSON: nil,
                status: "completed",
                createdAt: now, completedAt: now,
                resultURL: nil, errorMessage: nil
            ).insert(database)
        }

        let active = try runner.fetchActiveJobs()
        #expect(active.count == 1)

        let completed = try runner.fetchCompletedJobs()
        #expect(completed.count == 1)
    }

    @Test("MarkerOnly archives sets isArchived flag")
    @MainActor
    func testMarkerOnlySetsArchived() async throws {
        let (db, runner) = try makeEnv()

        let expId = UUID()
        let assetId1 = UUID()
        let assetId2 = UUID()
        let now = Date().timeIntervalSinceReferenceDate

        try await db.dbQueue.write { database in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Test Exp", subtitle: nil, description: nil,
                coverAssetId: nil, startDate: nil, endDate: nil,
                sourceMode: "sdCard", status: "reviewing",
                isMacPhotos: false, createdAt: now, updatedAt: now
            ).insert(database)

            try self.insertDummyAsset(database: database, id: assetId1, now: now)
            try self.insertDummyAsset(database: database, id: assetId2, now: now)

            try ExpeditionAssetRecord(
                id: UUID().uuidString,
                expeditionId: expId.uuidString,
                assetId: assetId1.uuidString,
                addedAt: now, addedBy: "sdImport", localOrder: 0,
                decision: "rejected", rating: nil, colorLabel: nil,
                isRecommended: false, isBestInGroup: false,
                isUserOverride: false, isArchived: false,
                isHiddenInExpedition: false, updatedAt: now
            ).insert(database)

            try ExpeditionAssetRecord(
                id: UUID().uuidString,
                expeditionId: expId.uuidString,
                assetId: assetId2.uuidString,
                addedAt: now, addedBy: "sdImport", localOrder: 1,
                decision: "rejected", rating: nil, colorLabel: nil,
                isRecommended: false, isBestInGroup: false,
                isUserOverride: false, isArchived: false,
                isHiddenInExpedition: false, updatedAt: now
            ).insert(database)
        }

        let job = try runner.submit(
            kind: .archiveMarkerOnly,
            expeditionId: expId,
            targetAssetIds: [assetId1, assetId2]
        )
        try await runner.run(job: job)

        let records = try await db.dbQueue.read { database in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expId.uuidString)
                .fetchAll(database)
        }
        #expect(records.allSatisfy { $0.isArchived == true })
    }

    @Test("MarkerOnly generates archive manifest")
    @MainActor
    func testMarkerOnlyGeneratesManifest() async throws {
        let (db, runner) = try makeEnv()

        let expId = UUID()
        let assetId = UUID()
        let now = Date().timeIntervalSinceReferenceDate

        try await db.dbQueue.write { database in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Exp", subtitle: nil, description: nil,
                coverAssetId: nil, startDate: nil, endDate: nil,
                sourceMode: "sdCard", status: "reviewing",
                isMacPhotos: false, createdAt: now, updatedAt: now
            ).insert(database)

            try self.insertDummyAsset(database: database, id: assetId, now: now)

            try ExpeditionAssetRecord(
                id: UUID().uuidString,
                expeditionId: expId.uuidString,
                assetId: assetId.uuidString,
                addedAt: now, addedBy: "sdImport", localOrder: 0,
                decision: "rejected", rating: nil, colorLabel: nil,
                isRecommended: false, isBestInGroup: false,
                isUserOverride: false, isArchived: false,
                isHiddenInExpedition: false, updatedAt: now
            ).insert(database)
        }

        let job = try runner.submit(
            kind: .archiveMarkerOnly,
            expeditionId: expId,
            targetAssetIds: [assetId]
        )
        try await runner.run(job: job)

        let manifests = try await db.dbQueue.read { database in
            try ArchiveManifestRecord
                .filter(Column("expeditionId") == expId.uuidString)
                .fetchAll(database)
        }
        #expect(manifests.count == 1)
        #expect(manifests[0].archiveKind == ArchiveKind.markerOnly.rawValue)

        let manifest = ArchiveManifest(record: manifests[0])
        #expect(manifest?.items.count == 1)
        #expect(manifest?.items.first?.assetId == assetId)
    }

    @Test("Run updates job status to completed on success")
    @MainActor
    func testRunUpdatesStatusCompleted() async throws {
        let (db, runner) = try makeEnv()

        let expId = UUID()
        let now = Date().timeIntervalSinceReferenceDate

        try await db.dbQueue.write { database in
            try ExpeditionRecord(
                id: expId.uuidString,
                name: "Exp", subtitle: nil, description: nil,
                coverAssetId: nil, startDate: nil, endDate: nil,
                sourceMode: "sdCard", status: "reviewing",
                isMacPhotos: false, createdAt: now, updatedAt: now
            ).insert(database)
        }

        let job = try runner.submit(
            kind: .archiveMarkerOnly,
            expeditionId: expId,
            targetAssetIds: []
        )
        try await runner.run(job: job)

        let record = try await db.dbQueue.read { database in
            try ActionJobRecord.fetchOne(database, key: job.id.uuidString)
        }
        #expect(record?.status == JobStatus.completed.rawValue)
        #expect(record?.completedAt != nil)
    }

    @Test("V3 compat: queued status maps to pending")
    @MainActor
    func testQueuedStatusCompat() throws {
        let (db, runner) = try makeEnv()

        let now = Date().timeIntervalSinceReferenceDate
        try db.dbQueue.write { database in
            try ActionJobRecord(
                id: UUID().uuidString,
                expeditionId: nil, albumId: nil,
                kind: "archiveVideo",
                targetAssetIdsJSON: nil,
                status: "queued",
                createdAt: now, completedAt: nil,
                resultURL: nil, errorMessage: nil
            ).insert(database)
        }

        let active = try runner.fetchActiveJobs()
        #expect(active.count == 1)
        #expect(active.first?.status == .pending)
    }

    @Test("ActionJob domain model roundtrip")
    func testActionJobRoundtrip() {
        let id = UUID()
        let expId = UUID()
        let assetIds = [UUID(), UUID(), UUID()]

        let record = ActionJobRecord(
            id: id.uuidString,
            expeditionId: expId.uuidString,
            albumId: nil,
            kind: ActionKind.archiveLowres.rawValue,
            targetAssetIdsJSON: "[\"\(assetIds[0].uuidString)\",\"\(assetIds[1].uuidString)\",\"\(assetIds[2].uuidString)\"]",
            status: "pending",
            createdAt: Date().timeIntervalSinceReferenceDate,
            completedAt: nil,
            resultURL: nil,
            errorMessage: nil
        )

        let job = ActionJob(record: record)
        #expect(job != nil)
        #expect(job?.id == id)
        #expect(job?.kind == .archiveLowres)
        #expect(job?.targetAssetIds.count == 3)
        #expect(job?.expeditionId == expId)

        let backToRecord = job!.toRecord()
        #expect(backToRecord.kind == "archiveLowres")
        #expect(backToRecord.status == "pending")
    }

    @Test("ArchiveManifest domain model roundtrip")
    func testArchiveManifestRoundtrip() {
        let item = ArchiveManifestItem(
            assetId: UUID(),
            originalReference: "/path/to/file.jpg",
            archivePath: "/archive/out.mp4",
            frameIndex: 5,
            decision: "rejected"
        )
        let manifest = ArchiveManifest(
            expeditionId: UUID(),
            archiveKind: .video,
            items: [item]
        )

        let record = manifest.toRecord()
        #expect(record.archiveKind == "video")

        let restored = ArchiveManifest(record: record)
        #expect(restored != nil)
        #expect(restored?.items.count == 1)
        #expect(restored?.items.first?.frameIndex == 5)
        #expect(restored?.archiveKind == .video)
    }

    @Test("Cancel ignores non-pending jobs")
    @MainActor
    func testCancelIgnoresNonPending() throws {
        let (db, runner) = try makeEnv()

        let now = Date().timeIntervalSinceReferenceDate
        let jobId = UUID()
        try db.dbQueue.write { database in
            try ActionJobRecord(
                id: jobId.uuidString,
                expeditionId: nil, albumId: nil,
                kind: "archiveVideo",
                targetAssetIdsJSON: nil,
                status: "completed",
                createdAt: now, completedAt: now,
                resultURL: nil, errorMessage: nil
            ).insert(database)
        }

        try runner.cancel(jobId: jobId)

        let record = try db.dbQueue.read { database in
            try ActionJobRecord.fetchOne(database, key: jobId.uuidString)
        }
        #expect(record?.status == "completed")
    }

    // MARK: - Helpers

    private func insertDummyAsset(database: Database, id: UUID, now: Double) throws {
        try MasterAssetRecord(
            id: id.uuidString,
            sourceId: nil, sourceKind: "sdCard", storageMode: "managed",
            externalIdentifier: nil, originalURL: nil, localManagedURL: nil,
            previewURL: nil, rawURL: nil, livePhotoVideoURL: nil,
            thumbnailCacheURL: nil, previewCacheURL: nil,
            fingerprint: nil, contentHash: nil,
            baseName: "test_\(id.uuidString.prefix(8))",
            mediaType: "photo", captureDate: now,
            latitude: nil, longitude: nil, focalLength: nil,
            aperture: nil, shutterSpeed: nil, iso: nil,
            cameraModel: nil, lensModel: nil,
            imageWidth: nil, imageHeight: nil,
            createdAt: now, updatedAt: now
        ).insert(database)
    }
}
