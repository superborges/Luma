import Foundation
import GRDB
import os

@MainActor
@Observable
final class ActionRunner {
    private let db: LumaDatabase
    private let actionJobRepo: any ActionJobRepository
    private let archiveManifestRepo: any ArchiveManifestRepository
    private let expeditionAssetRepo: any ExpeditionAssetRepository
    private let assetRepo: any MasterAssetRepository
    private let videoArchiver = VideoArchiver()
    private let folderExporter = FolderExporter()
    var albumManager: AlbumManager?
    var albumSyncAdapter: (any AlbumSyncAdapter)?
    var photoGroupRepo: (any PhotoGroupRepository)?
    var scoreRepo: (any AssetScoreRepository)?

    private static let logger = Logger(subsystem: "Luma", category: "ActionRunner")

    private(set) var currentJob: ActionJob?
    private(set) var progress: ArchiveProgress?
    private(set) var isRunning = false
    private(set) var lastExportResult: ExportResult?

    var exportOptions: ExportOptions = .default

    init(
        db: LumaDatabase,
        actionJobRepo: any ActionJobRepository,
        archiveManifestRepo: any ArchiveManifestRepository,
        expeditionAssetRepo: any ExpeditionAssetRepository,
        assetRepo: any MasterAssetRepository
    ) {
        self.db = db
        self.actionJobRepo = actionJobRepo
        self.archiveManifestRepo = archiveManifestRepo
        self.expeditionAssetRepo = expeditionAssetRepo
        self.assetRepo = assetRepo
    }

    // MARK: - Submit

    func submit(
        kind: ActionKind,
        expeditionId: UUID? = nil,
        albumId: UUID? = nil,
        targetAssetIds: [UUID] = []
    ) throws -> ActionJob {
        let jobRecord = ActionJobRecord(
            id: UUID().uuidString,
            expeditionId: expeditionId?.uuidString,
            albumId: albumId?.uuidString,
            kind: kind.rawValue,
            targetAssetIdsJSON: ActionJob.encodeAssetIds(targetAssetIds),
            status: JobStatus.pending.rawValue,
            createdAt: Date().timeIntervalSinceReferenceDate,
            completedAt: nil,
            resultURL: nil,
            errorMessage: nil
        )

        try actionJobRepo.insert(jobRecord)
        guard let job = ActionJob(record: jobRecord) else {
            throw LumaError.persistenceFailed("Failed to construct ActionJob from record")
        }
        return job
    }

    // MARK: - Run

    func run(job: ActionJob) async throws {
        guard !isRunning else {
            throw LumaError.unsupported("Another action is already running")
        }

        isRunning = true
        currentJob = job
        progress = nil
        lastExportResult = nil

        var record = job.toRecord()
        record.status = JobStatus.running.rawValue
        try actionJobRepo.update(record)

        do {
            var resultURL: URL?
            switch job.kind {
            case .archiveVideo:
                resultURL = try await runArchiveVideo(job: job)
            case .archiveLowres:
                resultURL = try await runArchiveLowres(job: job)
            case .archiveMarkerOnly:
                try await runMarkerOnly(job: job)
            case .exportToFolder:
                resultURL = try await runExportToFolder(job: job)
            case .syncAlbumToPhotos:
                try await runSyncAlbumToPhotos(job: job)
            }

            record.status = JobStatus.completed.rawValue
            record.completedAt = Date().timeIntervalSinceReferenceDate
            record.resultURL = resultURL?.absoluteString
            try actionJobRepo.update(record)
        } catch {
            record.status = JobStatus.failed.rawValue
            record.completedAt = Date().timeIntervalSinceReferenceDate
            record.errorMessage = error.localizedDescription
            try? actionJobRepo.update(record)
            isRunning = false
            currentJob = nil
            progress = nil
            throw error
        }

        isRunning = false
        currentJob = nil
        progress = nil
    }

    // MARK: - Cancel

    func cancel(jobId: UUID) throws {
        guard var record = try actionJobRepo.fetchOne(id: jobId.uuidString) else { return }
        guard record.status == JobStatus.pending.rawValue || record.status == "queued" else { return }
        record.status = JobStatus.cancelled.rawValue
        record.completedAt = Date().timeIntervalSinceReferenceDate
        try actionJobRepo.update(record)

        if currentJob?.id == jobId {
            currentJob = nil
            isRunning = false
            progress = nil
        }
    }

    // MARK: - Fetch

    func fetchActiveJobs() throws -> [ActionJob] {
        try actionJobRepo.fetchActive().compactMap { ActionJob(record: $0) }
    }

    func fetchCompletedJobs() throws -> [ActionJob] {
        try actionJobRepo.fetchCompleted().compactMap { ActionJob(record: $0) }
    }

    // MARK: - Archive Video Handler

    private func runArchiveVideo(job: ActionJob) async throws -> URL? {
        let assets = try fetchMasterAssets(ids: job.targetAssetIds)
        guard !assets.isEmpty else {
            throw LumaError.unsupported("No assets available for archive video")
        }

        let expeditionName = job.expeditionId.flatMap { eid -> String? in
            try? db.dbQueue.read { db in
                try ExpeditionRecord.fetchOne(db, key: eid.uuidString)?.name
            }
        } ?? "Archive"

        let outputDir = try AppDirectories.applicationSupportRoot()
            .appendingPathComponent("Archives", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("\(expeditionName)_archive.mp4")

        let result = try await videoArchiver.archive(
            masterAssets: assets,
            title: expeditionName,
            outputURL: outputURL
        ) { [weak self] prog in
            Task { @MainActor in
                self?.progress = prog
            }
        }

        try markAssetsArchived(assetIds: job.targetAssetIds, expeditionId: job.expeditionId)

        let manifestItems = assets.enumerated().map { index, asset in
            ArchiveManifestItem(
                assetId: asset.id,
                originalReference: asset.originalURL?.absoluteString ?? asset.previewURL?.absoluteString,
                archivePath: result.outputURL?.absoluteString,
                frameIndex: index,
                decision: "rejected"
            )
        }
        let manifest = ArchiveManifest(
            expeditionId: job.expeditionId,
            archiveKind: .video,
            items: manifestItems
        )
        try archiveManifestRepo.insert(manifest.toRecord())

        return result.outputURL
    }

    // MARK: - Archive Lowres Handler

    private func runArchiveLowres(job: ActionJob) async throws -> URL? {
        let assets = try fetchMasterAssets(ids: job.targetAssetIds)
        guard !assets.isEmpty else {
            throw LumaError.unsupported("No assets available for shrink-keep")
        }

        let baseDir = try AppDirectories.applicationSupportRoot()
            .appendingPathComponent("Archives", isDirectory: true)
        let outputDir = baseDir.appendingPathComponent("lowres_\(job.id.uuidString.prefix(8))")

        let result = try await videoArchiver.shrinkKeep(
            masterAssets: assets,
            outputDirectory: outputDir
        ) { [weak self] prog in
            Task { @MainActor in
                self?.progress = prog
            }
        }

        try markAssetsArchived(assetIds: job.targetAssetIds, expeditionId: job.expeditionId)

        let manifestItems = assets.map { asset in
            ArchiveManifestItem(
                assetId: asset.id,
                originalReference: asset.originalURL?.absoluteString ?? asset.previewURL?.absoluteString,
                archivePath: outputDir.appendingPathComponent("\(asset.baseName).jpg").absoluteString,
                frameIndex: nil,
                decision: "rejected"
            )
        }
        let manifest = ArchiveManifest(
            expeditionId: job.expeditionId,
            archiveKind: .lowresCopy,
            items: manifestItems
        )
        try archiveManifestRepo.insert(manifest.toRecord())

        return result.outputURL
    }

    // MARK: - Marker Only Handler

    private func runMarkerOnly(job: ActionJob) async throws {
        try markAssetsArchived(assetIds: job.targetAssetIds, expeditionId: job.expeditionId)

        let manifestItems = job.targetAssetIds.map { assetId in
            ArchiveManifestItem(
                assetId: assetId,
                originalReference: nil,
                archivePath: nil,
                frameIndex: nil,
                decision: "rejected"
            )
        }
        let manifest = ArchiveManifest(
            expeditionId: job.expeditionId,
            archiveKind: .markerOnly,
            items: manifestItems
        )
        try archiveManifestRepo.insert(manifest.toRecord())
    }

    // MARK: - Export to Folder Handler

    private func runExportToFolder(job: ActionJob) async throws -> URL? {
        let assets = try fetchMasterAssets(ids: job.targetAssetIds)
        guard !assets.isEmpty else {
            throw LumaError.unsupported("No assets available for folder export")
        }

        let groups = fetchGroupsForExpedition(expeditionId: job.expeditionId)
        let ratings = fetchRatingsForAssets(ids: job.targetAssetIds)

        let result = try await folderExporter.export(
            masterAssets: assets,
            groups: groups,
            ratings: ratings,
            options: exportOptions
        ) { [weak self] completed, total, name in
            Task { @MainActor in
                self?.progress = ArchiveProgress(completed: completed, total: total, currentName: name)
            }
        }

        lastExportResult = result
        return result.destinationURL
    }

    // MARK: - Sync Album to Photos Handler

    private func runSyncAlbumToPhotos(job: ActionJob) async throws {
        guard let albumId = job.albumId,
              let mgr = albumManager,
              let adapter = albumSyncAdapter else {
            throw LumaError.unsupported("Album sync requires album manager and adapter")
        }

        let assetIds = try mgr.fetchAlbumAssetIds(albumId: albumId)
        guard !assetIds.isEmpty else { return }

        let records = try assetRepo.fetchByIds(assetIds.map(\.uuidString))
        let lookup = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let assets = assetIds.compactMap { lookup[$0.uuidString].flatMap { MasterAsset(record: $0) } }

        let existingRef = try mgr.fetchExternalRef(albumId: albumId)

        if let ref = existingRef {
            try await adapter.updateAlbum(ref, assets: assets)
        } else {
            guard let album = try mgr.fetchAlbum(id: albumId) else {
                throw LumaError.persistenceFailed("Album not found")
            }
            var ref = try await adapter.createAlbum(name: album.name, assets: assets)
            ref.albumId = albumId
            try mgr.markAlbumAsSynced(albumId: albumId, ref: ref)
        }
    }

    // MARK: - Helpers

    private func fetchGroupsForExpedition(expeditionId: UUID?) -> [PhotoGroupWithAssets] {
        guard let expId = expeditionId, let repo = photoGroupRepo else { return [] }
        do {
            let groupRecords = try repo.fetchByExpedition(expId.uuidString)

            let expAssetRecords = try db.dbQueue.read { db in
                try ExpeditionAssetRecord
                    .filter(Column("expeditionId") == expId.uuidString)
                    .fetchAll(db)
            }
            let masterRecords = try assetRepo.fetchByIds(expAssetRecords.map(\.assetId))
            let masterMap = Dictionary(masterRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })

            let eaMap = Dictionary(
                expAssetRecords.map { ($0.assetId, $0) },
                uniquingKeysWith: { _, b in b }
            )

            return groupRecords.compactMap { record in
                let assetRecords = (try? repo.fetchAssetsForGroup(record.id)) ?? []
                let groupAssets: [ExpeditionAssetWithMaster] = assetRecords.compactMap { pgRecord in
                    guard let mr = masterMap[pgRecord.assetId],
                          let ma = MasterAsset(record: mr),
                          let ea = eaMap[pgRecord.assetId].flatMap({ ExpeditionAsset(record: $0) }) else {
                        return nil
                    }
                    return ExpeditionAssetWithMaster(
                        expeditionAsset: ea,
                        masterAsset: ma,
                        latestScore: nil
                    )
                }
                let recommendedIds = assetRecords
                    .filter(\.isRecommended)
                    .compactMap { UUID(uuidString: $0.assetId) }
                return PhotoGroupWithAssets(
                    record: record,
                    assets: groupAssets,
                    recommendedAssetIds: recommendedIds
                )
            }
        } catch { return [] }
    }

    private func fetchRatingsForAssets(ids: [UUID]) -> [UUID: Int] {
        guard let repo = scoreRepo else { return [:] }
        let idStrs = ids.map(\.uuidString)
        let scores = (try? repo.fetchLatestByAssets(idStrs)) ?? [:]
        var ratings: [UUID: Int] = [:]
        for (idStr, score) in scores {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let overall = score.overall ?? 50
            let rating: Int
            switch overall {
            case 90...: rating = 5
            case 75..<90: rating = 4
            case 60..<75: rating = 3
            case 45..<60: rating = 2
            default: rating = 1
            }
            ratings[uuid] = rating
        }
        return ratings
    }

    private func fetchMasterAssets(ids: [UUID]) throws -> [MasterAsset] {
        let records = try assetRepo.fetchByIds(ids.map(\.uuidString))
        let lookup = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { lookup[$0.uuidString].flatMap { MasterAsset(record: $0) } }
    }

    private func markAssetsArchived(assetIds: [UUID], expeditionId: UUID?) throws {
        guard let eid = expeditionId else { return }
        try db.dbQueue.write { db in
            for assetId in assetIds {
                if var record = try ExpeditionAssetRecord
                    .filter(Column("expeditionId") == eid.uuidString && Column("assetId") == assetId.uuidString)
                    .fetchOne(db)
                {
                    record.isArchived = true
                    record.updatedAt = Date().timeIntervalSinceReferenceDate
                    try record.update(db)
                }
            }
        }
    }

}
