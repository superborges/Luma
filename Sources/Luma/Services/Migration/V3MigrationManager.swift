import Foundation
import GRDB
import os

struct MigrationEstimate: Sendable {
    let sessionCount: Int
    let totalAssetCount: Int
    let estimatedTimeSeconds: Int
}

struct MigrationProgress: Sendable {
    let currentSession: Int
    let totalSessions: Int
    let currentSessionName: String
    let currentAsset: Int
    let totalAssets: Int
    let phase: MigrationPhase
}

enum MigrationPhase: String, Sendable {
    case backup
    case migratingSession
    case writingMarker
    case completed
    case failed
}

final class V3MigrationManager: Sendable {

    private let db: LumaDatabase
    private let assetSourceManager: AssetSourceManager
    private let expeditionManager: ExpeditionManager
    private let assetManager: AssetManager
    private let photoGroupRepo: any PhotoGroupRepository
    private let scoreRepo: any AssetScoreRepository
    private let importSessionRepo: any ImportSessionRepository

    private static let logger = Logger(subsystem: "Luma", category: "V3Migration")
    private static let markerFileName = "migration_completed_v4"

    init(
        db: LumaDatabase,
        assetSourceManager: AssetSourceManager,
        expeditionManager: ExpeditionManager,
        assetManager: AssetManager,
        photoGroupRepo: any PhotoGroupRepository,
        scoreRepo: any AssetScoreRepository,
        importSessionRepo: any ImportSessionRepository
    ) {
        self.db = db
        self.assetSourceManager = assetSourceManager
        self.expeditionManager = expeditionManager
        self.assetManager = assetManager
        self.photoGroupRepo = photoGroupRepo
        self.scoreRepo = scoreRepo
        self.importSessionRepo = importSessionRepo
    }

    // MARK: - Detection

    func needsMigration() throws -> Bool {
        let root = try AppDirectories.applicationSupportRoot()
        let markerPath = root.appendingPathComponent(Self.markerFileName).path
        if FileManager.default.fileExists(atPath: markerPath) { return false }
        return !findSessionDirectories().isEmpty
    }

    func estimateMigrationScope() -> MigrationEstimate {
        let dirs = findSessionDirectories()
        var totalAssets = 0
        let decoder = JSONDecoder.lumaDecoder
        for dir in dirs {
            let manifestURL = AppDirectories.manifestURL(in: dir)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(SessionManifest.self, from: data) else { continue }
            totalAssets += manifest.assets.count
        }
        let seconds = max(1, dirs.count * 2 + totalAssets / 50)
        return MigrationEstimate(sessionCount: dirs.count, totalAssetCount: totalAssets, estimatedTimeSeconds: seconds)
    }

    // MARK: - Migration

    func performMigration(onProgress: @Sendable @escaping (MigrationProgress) -> Void) async throws {
        let dirs = findSessionDirectories()
        guard !dirs.isEmpty else { return }

        let decoder = JSONDecoder.lumaDecoder
        let totalSessions = dirs.count

        onProgress(MigrationProgress(
            currentSession: 0, totalSessions: totalSessions,
            currentSessionName: "", currentAsset: 0, totalAssets: 0,
            phase: .backup
        ))

        try backupManifests(dirs)

        var totalMigratedAssets = 0
        var skippedSessions = 0
        var sourceCache: [String: AssetSource] = [:]
        var masterAssetHashIndex: [String: UUID] = [:]

        try buildExistingHashIndex(&masterAssetHashIndex)

        for (index, dir) in dirs.enumerated() {
            if isSessionAlreadyMigrated(dir) {
                Self.logger.info("Session already migrated, skipping: \(dir.lastPathComponent)")
                continue
            }

            let manifestURL = AppDirectories.manifestURL(in: dir)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(SessionManifest.self, from: data) else {
                Self.logger.warning("Skipping unreadable manifest at \(dir.path)")
                skippedSessions += 1
                continue
            }

            let sessionName = manifest.name
            onProgress(MigrationProgress(
                currentSession: index + 1, totalSessions: totalSessions,
                currentSessionName: sessionName,
                currentAsset: 0, totalAssets: manifest.assets.count,
                phase: .migratingSession
            ))

            try migrateOneSession(
                manifest: manifest,
                projectDirectory: dir,
                sourceCache: &sourceCache,
                masterAssetHashIndex: &masterAssetHashIndex,
                onAssetProgress: { current, total in
                    onProgress(MigrationProgress(
                        currentSession: index + 1, totalSessions: totalSessions,
                        currentSessionName: sessionName,
                        currentAsset: current, totalAssets: total,
                        phase: .migratingSession
                    ))
                }
            )
            totalMigratedAssets += manifest.assets.count

            try markSessionMigrated(dir)
        }

        if skippedSessions > 0 {
            Self.logger.error("Migration skipped \(skippedSessions) session(s) due to unreadable manifests — marker NOT written")
            throw LumaError.persistenceFailed(
                "迁移跳过了 \(skippedSessions) 个旅程（manifest 无法读取），请检查数据目录后重试。"
            )
        }

        onProgress(MigrationProgress(
            currentSession: totalSessions, totalSessions: totalSessions,
            currentSessionName: "", currentAsset: 0, totalAssets: 0,
            phase: .writingMarker
        ))

        try writeMarker(sessionCount: totalSessions, assetCount: totalMigratedAssets)

        onProgress(MigrationProgress(
            currentSession: totalSessions, totalSessions: totalSessions,
            currentSessionName: "", currentAsset: 0, totalAssets: 0,
            phase: .completed
        ))
    }

    // MARK: - Private Helpers

    private func findSessionDirectories() -> [URL] {
        do {
            return try AppDirectories.projectDirectories()
        } catch {
            Self.logger.error("Cannot list project directories: \(error.localizedDescription)")
            return []
        }
    }

    private func backupManifests(_ dirs: [URL]) throws {
        let root = try AppDirectories.applicationSupportRoot()
        let backupRoot = root.appendingPathComponent("migration-backup")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        for dir in dirs {
            let manifestURL = AppDirectories.manifestURL(in: dir)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

            let dirName = dir.lastPathComponent
            let destDir = backupRoot.appendingPathComponent(dirName)
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destFile = destDir.appendingPathComponent("manifest.json")
            if !FileManager.default.fileExists(atPath: destFile.path) {
                try FileManager.default.copyItem(at: manifestURL, to: destFile)
            }
        }
    }

    private func buildExistingHashIndex(_ index: inout [String: UUID]) throws {
        let existing = try db.dbQueue.read { db in
            try MasterAssetRecord
                .select(Column("id"), Column("contentHash"))
                .fetchAll(db)
        }
        for record in existing {
            if let hash = record.contentHash {
                index[hash] = UUID(uuidString: record.id)
            }
        }
    }

    func migrateOneSession(
        manifest: SessionManifest,
        projectDirectory: URL,
        sourceCache: inout [String: AssetSource],
        masterAssetHashIndex: inout [String: UUID],
        onAssetProgress: (_ current: Int, _ total: Int) -> Void
    ) throws {
        let session = manifest.session
        let assets = session.assets
        let groups = session.groups

        let sourceMode = inferSourceMode(assets: assets)
        let status = inferExpeditionStatus(session: session)
        let dateRange = inferDateRange(assets: assets)

        let expedition = try expeditionManager.createExpedition(
            name: session.name,
            subtitle: session.location,
            sourceMode: sourceMode,
            status: status,
            startDate: dateRange?.lowerBound,
            endDate: dateRange?.upperBound,
            coverAssetId: nil,
            createdAt: session.createdAt,
            isMacPhotos: false
        )

        var assetIdMapping: [UUID: UUID] = [:]

        for (assetIndex, mediaAsset) in assets.enumerated() {
            onAssetProgress(assetIndex + 1, assets.count)

            let source = try resolveOrCreateSource(
                importSource: mediaAsset.source,
                cache: &sourceCache
            )
            let (sourceKind, storageMode) = mapImportSourceToV4(mediaAsset.source)

            let contentHash = computeContentHash(for: mediaAsset, in: projectDirectory)

            if let hash = contentHash, let existingId = masterAssetHashIndex[hash] {
                assetIdMapping[mediaAsset.id] = existingId
                try createExpeditionAsset(
                    expeditionId: expedition.id,
                    masterAssetId: existingId,
                    mediaAsset: mediaAsset,
                    importSessions: session.importSessions
                )
                try migrateAIScore(mediaAsset: mediaAsset, masterAssetId: existingId)
                continue
            }

            let masterAssetId = mediaAsset.id
            assetIdMapping[mediaAsset.id] = masterAssetId

            let now = Date().timeIntervalSinceReferenceDate
            let externalIdentifier: String? = {
                if case .photosLibrary(let localId) = mediaAsset.source { return localId }
                return nil
            }()

            let (originalURL, localManagedURL) = resolveURLs(mediaAsset: mediaAsset, storageMode: storageMode)

            let record = MasterAssetRecord(
                id: masterAssetId.uuidString,
                sourceId: source.id.uuidString,
                sourceKind: sourceKind.rawValue,
                storageMode: storageMode.rawValue,
                externalIdentifier: externalIdentifier,
                originalURL: originalURL?.absoluteString,
                localManagedURL: localManagedURL?.absoluteString,
                previewURL: mediaAsset.previewURL?.absoluteString,
                rawURL: mediaAsset.rawURL?.absoluteString,
                livePhotoVideoURL: mediaAsset.livePhotoVideoURL?.absoluteString,
                thumbnailCacheURL: mediaAsset.thumbnailURL?.absoluteString,
                previewCacheURL: nil,
                fingerprint: nil,
                contentHash: contentHash,
                baseName: mediaAsset.baseName,
                mediaType: mediaAsset.mediaType.rawValue,
                captureDate: mediaAsset.metadata.captureDate.timeIntervalSinceReferenceDate,
                latitude: mediaAsset.metadata.gpsCoordinate?.latitude,
                longitude: mediaAsset.metadata.gpsCoordinate?.longitude,
                focalLength: mediaAsset.metadata.focalLength,
                aperture: mediaAsset.metadata.aperture,
                shutterSpeed: mediaAsset.metadata.shutterSpeed,
                iso: mediaAsset.metadata.iso,
                cameraModel: mediaAsset.metadata.cameraModel,
                lensModel: mediaAsset.metadata.lensModel,
                imageWidth: mediaAsset.metadata.imageWidth,
                imageHeight: mediaAsset.metadata.imageHeight,
                createdAt: now,
                updatedAt: now
            )
            try db.dbQueue.write { db in
                try record.insert(db)
            }

            if let hash = contentHash {
                masterAssetHashIndex[hash] = masterAssetId
            }

            try createExpeditionAsset(
                expeditionId: expedition.id,
                masterAssetId: masterAssetId,
                mediaAsset: mediaAsset,
                importSessions: session.importSessions
            )
            try migrateAIScore(mediaAsset: mediaAsset, masterAssetId: masterAssetId)
        }

        if let v3Cover = session.coverAssetID,
           let mappedCover = assetIdMapping[v3Cover] {
            try expeditionManager.setExpeditionCover(
                expeditionId: expedition.id, assetId: mappedCover
            )
        }

        try migrateGroups(
            groups: groups,
            expeditionId: expedition.id,
            assetIdMapping: assetIdMapping
        )

        try migrateImportSessions(
            importSessions: session.importSessions,
            expeditionId: expedition.id,
            sourceCache: sourceCache
        )

        try migrateExportJobs(
            exportJobs: session.exportJobs,
            expeditionId: expedition.id,
            assetIdMapping: assetIdMapping
        )
    }

    // MARK: - Source Mapping

    private func resolveOrCreateSource(
        importSource: ImportSource,
        cache: inout [String: AssetSource]
    ) throws -> AssetSource {
        let cacheKey: String
        let kind: AssetSourceKind
        let displayName: String
        let rootIdentifier: String?

        switch importSource {
        case .folder(let path):
            cacheKey = "folder:\(path)"
            kind = .localFolder
            displayName = URL(fileURLWithPath: path).lastPathComponent
            rootIdentifier = path
        case .sdCard(let volumePath):
            cacheKey = "sdCard:\(volumePath)"
            kind = .sdCard
            displayName = URL(fileURLWithPath: volumePath).lastPathComponent
            rootIdentifier = volumePath
        case .photosLibrary(let localId):
            cacheKey = "macPhotos:\(localId)"
            kind = .macPhotos
            displayName = "Mac Photos"
            rootIdentifier = localId
        case .iPhone(let deviceID):
            cacheKey = "sdCard:\(deviceID)"
            kind = .sdCard
            displayName = "iPhone (\(deviceID))"
            rootIdentifier = deviceID
        }

        if let cached = cache[cacheKey] { return cached }
        let source = try assetSourceManager.registerSource(
            kind: kind, displayName: displayName, rootIdentifier: rootIdentifier
        )
        cache[cacheKey] = source
        return source
    }

    private func mapImportSourceToV4(_ source: ImportSource) -> (AssetSourceKind, AssetStorageMode) {
        switch source {
        case .folder: return (.localFolder, .managed)
        case .sdCard: return (.sdCard, .managed)
        case .photosLibrary: return (.macPhotos, .externalReference)
        case .iPhone: return (.sdCard, .managed)
        }
    }

    private func inferSourceMode(assets: [MediaAsset]) -> ExpeditionSourceMode {
        var kinds = Set<String>()
        for a in assets {
            switch a.source {
            case .folder: kinds.insert("folder")
            case .sdCard: kinds.insert("sdCard")
            case .photosLibrary: kinds.insert("macPhotos")
            case .iPhone: kinds.insert("sdCard")
            }
        }
        if kinds.count > 1 { return .mixed }
        switch kinds.first {
        case "folder": return .localFolder
        case "sdCard": return .sdCard
        case "macPhotos": return .macPhotos
        default: return .sdCard
        }
    }

    private func inferExpeditionStatus(session: Session) -> ExpeditionStatus {
        let hasUnreviewed = session.assets.contains { $0.userDecision == .pending }
        let hasExport = session.exportJobs.contains { $0.status == .completed }
        if session.isArchived == true { return .archived }
        if hasExport { return .completed }
        if !hasUnreviewed && !session.assets.isEmpty { return .completed }
        return .reviewing
    }

    private func inferDateRange(assets: [MediaAsset]) -> ClosedRange<Date>? {
        let dates = assets.compactMap { $0.metadata.captureDate == .distantPast ? nil : $0.metadata.captureDate }
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        return earliest...latest
    }

    // MARK: - URL Resolution

    private func resolveURLs(mediaAsset: MediaAsset, storageMode: AssetStorageMode) -> (URL?, URL?) {
        switch storageMode {
        case .managed:
            return (nil, mediaAsset.rawURL ?? mediaAsset.previewURL)
        case .referenced:
            return (mediaAsset.rawURL ?? mediaAsset.previewURL, nil)
        case .externalReference:
            return (mediaAsset.rawURL ?? mediaAsset.previewURL, nil)
        }
    }

    // MARK: - Content Hash

    private func computeContentHash(for asset: MediaAsset, in projectDirectory: URL) -> String? {
        guard let url = asset.rawURL ?? asset.previewURL ?? asset.thumbnailURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? AssetManager.computeContentHash(fileURL: url)
    }

    // MARK: - ExpeditionAsset

    private func createExpeditionAsset(
        expeditionId: UUID,
        masterAssetId: UUID,
        mediaAsset: MediaAsset,
        importSessions: [ImportSession]
    ) throws {
        let addedBy: AssetAddedBy
        if let firstSession = importSessions.first {
            addedBy = .importSession(firstSession.id.uuidString)
        } else {
            addedBy = .manualAdd
        }

        try assetManager.addAssetToExpedition(
            expeditionId: expeditionId,
            assetId: masterAssetId,
            addedBy: addedBy,
            decision: mediaAsset.userDecision,
            rating: mediaAsset.userRating,
            isRecommended: mediaAsset.aiScore?.recommended ?? false
        )
    }

    // MARK: - AI Score

    private func migrateAIScore(mediaAsset: MediaAsset, masterAssetId: UUID) throws {
        guard let aiScore = mediaAsset.aiScore else { return }
        let record = AssetScoreRecord(
            id: UUID().uuidString,
            assetId: masterAssetId.uuidString,
            provider: aiScore.provider,
            composition: aiScore.scores.composition,
            exposure: aiScore.scores.exposure,
            color: aiScore.scores.color,
            sharpness: aiScore.scores.sharpness,
            story: aiScore.scores.story,
            overall: aiScore.overall,
            comment: aiScore.comment,
            recommended: aiScore.recommended,
            timestamp: aiScore.timestamp.timeIntervalSinceReferenceDate
        )
        try scoreRepo.insert(record)
    }

    // MARK: - Groups

    private func migrateGroups(
        groups: [PhotoGroup],
        expeditionId: UUID,
        assetIdMapping: [UUID: UUID]
    ) throws {
        let now = Date().timeIntervalSinceReferenceDate
        for group in groups {
            let groupRecord = PhotoGroupRecord(
                id: group.id.uuidString,
                expeditionId: expeditionId.uuidString,
                name: group.name,
                coverAssetId: nil,
                groupComment: group.groupComment,
                timeRangeStart: group.timeRange.lowerBound.timeIntervalSinceReferenceDate,
                timeRangeEnd: group.timeRange.upperBound.timeIntervalSinceReferenceDate,
                latitude: group.location?.latitude,
                longitude: group.location?.longitude,
                reviewed: false,
                createdAt: now,
                updatedAt: now
            )
            try photoGroupRepo.insert(groupRecord)

            let recommendedSet = Set(group.recommendedAssets)
            for assetId in group.assets {
                guard let mappedId = assetIdMapping[assetId] else { continue }
                let assetRecord = PhotoGroupAssetRecord(
                    groupId: group.id.uuidString,
                    assetId: mappedId.uuidString,
                    isRecommended: recommendedSet.contains(assetId)
                )
                do {
                    try photoGroupRepo.addAsset(assetRecord)
                } catch {
                    Self.logger.warning("Failed to add asset \(mappedId) to group \(group.id): \(error)")
                }
            }

            for sub in group.subGroups {
                let subRecord = PhotoSubGroupRecord(
                    id: sub.id.uuidString,
                    groupId: group.id.uuidString,
                    bestAssetId: sub.bestAsset.flatMap { assetIdMapping[$0]?.uuidString },
                    recommendedAssetId: nil,
                    reasonSummary: nil,
                    reviewed: false
                )
                try db.dbQueue.write { db in
                    try subRecord.insert(db)
                }
                for subAssetId in sub.assets {
                    guard let mappedId = assetIdMapping[subAssetId] else { continue }
                    let subAssetRecord = PhotoSubGroupAssetRecord(
                        subgroupId: sub.id.uuidString,
                        assetId: mappedId.uuidString
                    )
                    try db.dbQueue.write { db in
                        try subAssetRecord.insert(db)
                    }
                }
            }
        }
    }

    // MARK: - Import Sessions

    private func migrateImportSessions(
        importSessions: [ImportSession],
        expeditionId: UUID,
        sourceCache: [String: AssetSource]
    ) throws {
        for session in importSessions {
            let sourceId = resolveImportSessionSourceId(session: session, sourceCache: sourceCache)
            let record = ImportSessionRecord(
                id: session.id.uuidString,
                sourceId: sourceId,
                targetExpeditionId: expeditionId.uuidString,
                startedAt: session.createdAt.timeIntervalSinceReferenceDate,
                completedAt: session.completedAt?.timeIntervalSinceReferenceDate,
                status: session.status.rawValue,
                totalItems: session.totalItems,
                importedCount: session.completedOriginals,
                skippedCount: 0,
                failedItems: session.lastError
            )
            try importSessionRepo.insert(record)
        }
    }

    private func resolveImportSessionSourceId(
        session: ImportSession,
        sourceCache: [String: AssetSource]
    ) -> String? {
        switch session.source {
        case .folder(let path, _):
            return sourceCache["folder:\(path)"]?.id.uuidString
        case .sdCard(let volumePath, _):
            return sourceCache["sdCard:\(volumePath)"]?.id.uuidString
        case .photosLibrary(let albumId, _, _):
            return albumId.flatMap { sourceCache["macPhotos:\($0)"]?.id.uuidString }
        case .iPhone(let deviceID, _):
            return sourceCache["sdCard:\(deviceID)"]?.id.uuidString
        }
    }

    // MARK: - Export Jobs

    private func migrateExportJobs(
        exportJobs: [ExportJob],
        expeditionId: UUID,
        assetIdMapping: [UUID: UUID]
    ) throws {
        for job in exportJobs {
            let targetIds = job.targetAssetIDs.compactMap { assetIdMapping[$0] }
            let targetIdsJSON = try? String(data: JSONEncoder().encode(targetIds.map(\.uuidString)), encoding: .utf8)
            let record = ActionJobRecord(
                id: job.id.uuidString,
                expeditionId: expeditionId.uuidString,
                albumId: nil,
                kind: "exportCopyToFolder",
                targetAssetIdsJSON: targetIdsJSON,
                status: job.status.rawValue,
                createdAt: job.createdAt.timeIntervalSinceReferenceDate,
                completedAt: job.completedAt?.timeIntervalSinceReferenceDate,
                resultURL: nil,
                errorMessage: job.lastError
            )
            try db.dbQueue.write { db in
                try record.insert(db)
            }
        }
    }

    // MARK: - Migration Marker & Per-Session Tracking

    private static let perSessionMarkerDir = "migration-progress"

    private func markSessionMigrated(_ dir: URL) throws {
        let root = try AppDirectories.applicationSupportRoot()
        let progressDir = root.appendingPathComponent(Self.perSessionMarkerDir)
        try FileManager.default.createDirectory(at: progressDir, withIntermediateDirectories: true)
        let markerFile = progressDir.appendingPathComponent(dir.lastPathComponent)
        try Data().write(to: markerFile)
    }

    private func isSessionAlreadyMigrated(_ dir: URL) -> Bool {
        guard let root = try? AppDirectories.applicationSupportRoot() else { return false }
        let markerFile = root
            .appendingPathComponent(Self.perSessionMarkerDir)
            .appendingPathComponent(dir.lastPathComponent)
        return FileManager.default.fileExists(atPath: markerFile.path)
    }

    private func writeMarker(sessionCount: Int, assetCount: Int) throws {
        let root = try AppDirectories.applicationSupportRoot()
        let markerURL = root.appendingPathComponent(Self.markerFileName)
        let info: [String: Any] = [
            "migratedAt": ISO8601DateFormatter().string(from: Date()),
            "sessionCount": sessionCount,
            "assetCount": assetCount,
            "version": "4.0"
        ]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: markerURL)
    }
}

