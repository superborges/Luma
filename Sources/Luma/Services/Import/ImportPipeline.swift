import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

struct ImportResult: Sendable {
    let importedAssets: [MasterAsset]
    let createdExpeditionAssets: [ExpeditionAsset]
    let duplicateCount: Int
    let groupCount: Int
    let sessionId: UUID
}

private actor PipelineConnectionTracker {
    private let sourceName: String
    private var latestState: ConnectionState = .connected

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func update(_ state: ConnectionState) {
        latestState = state
    }

    func ensureConnected() throws {
        switch latestState {
        case .connected, .scanning:
            return
        case .disconnected:
            throw LumaError.importFailed("\(sourceName) 已断开连接，请重新连接后继续导入。")
        case .unavailable:
            throw LumaError.importFailed("\(sourceName) 当前不可访问。")
        }
    }
}

struct ImportPipeline: Sendable {
    let db: LumaDatabase
    let assetManager: AssetManager
    let photoGroupRepo: any PhotoGroupRepository
    let importSessionRepo: any ImportSessionRepository
    let groupingEngine: GroupingEngine

    private static let logger = Logger(subsystem: "Luma", category: "ImportPipeline")

    init(
        db: LumaDatabase,
        assetManager: AssetManager,
        photoGroupRepo: any PhotoGroupRepository,
        importSessionRepo: any ImportSessionRepository,
        groupingEngine: GroupingEngine = GroupingEngine()
    ) {
        self.db = db
        self.assetManager = assetManager
        self.photoGroupRepo = photoGroupRepo
        self.importSessionRepo = importSessionRepo
        self.groupingEngine = groupingEngine
    }

    /// V4 导入核心入口：枚举 → 去重 → 双写 → 三阶段拷贝 → 分组
    func addPhotosToExpedition(
        adapter: any AssetSourceAdapter,
        expeditionId: UUID,
        options: SourceEnumerationOptions = SourceEnumerationOptions(),
        onProgress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult {
        let startedAt = Date().timeIntervalSinceReferenceDate
        let sessionId = UUID()
        do {
            return try await performImport(
                adapter: adapter, expeditionId: expeditionId,
                sessionId: sessionId, options: options,
                startedAt: startedAt, onProgress: onProgress
            )
        } catch {
            Self.logger.error("Import failed for session \(sessionId): \(error.localizedDescription)")
            let failedRecord = ImportSessionRecord(
                id: sessionId.uuidString,
                sourceId: adapter.source.id.uuidString,
                targetExpeditionId: expeditionId.uuidString,
                startedAt: startedAt,
                completedAt: Date().timeIntervalSinceReferenceDate,
                status: "failed",
                totalItems: 0, importedCount: 0, skippedCount: 0,
                failedItems: error.localizedDescription
            )
            try? importSessionRepo.insert(failedRecord)
            throw error
        }
    }

    private func performImport(
        adapter: any AssetSourceAdapter,
        expeditionId: UUID,
        sessionId: UUID,
        options: SourceEnumerationOptions,
        startedAt: Double,
        onProgress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult {
        let connectionTracker = PipelineConnectionTracker(sourceName: adapter.displayName)

        let connectionMonitorTask = Task {
            for await state in adapter.connectionState {
                await connectionTracker.update(state)
            }
        }
        defer { connectionMonitorTask.cancel() }

        // Phase 0: Enumerate
        onProgress(ImportProgress(
            phase: .scanning, completed: 0, total: 1,
            currentItemName: adapter.displayName
        ))

        try await connectionTracker.ensureConnected()
        let discoveredAssets = try await adapter.enumerateAssets(options: options)

        guard !discoveredAssets.isEmpty else {
            Self.logger.log("No assets discovered from \(adapter.displayName, privacy: .public)")
            let emptyRecord = ImportSessionRecord(
                id: sessionId.uuidString,
                sourceId: adapter.source.id.uuidString,
                targetExpeditionId: expeditionId.uuidString,
                startedAt: Date().timeIntervalSinceReferenceDate,
                completedAt: Date().timeIntervalSinceReferenceDate,
                status: "completed",
                totalItems: 0, importedCount: 0, skippedCount: 0,
                failedItems: nil
            )
            try importSessionRepo.insert(emptyRecord)
            return ImportResult(
                importedAssets: [], createdExpeditionAssets: [],
                duplicateCount: 0, groupCount: 0, sessionId: sessionId
            )
        }

        let total = discoveredAssets.count

        // Phase 1: Create MasterAsset + ExpeditionAsset (dedup + thumbnails)
        var masterAssets: [MasterAsset] = []
        var expeditionAssets: [ExpeditionAsset] = []
        var duplicateCount = 0
        var seenMasterAssetIds = Set<UUID>()
        masterAssets.reserveCapacity(total)
        expeditionAssets.reserveCapacity(total)

        for (index, discovered) in discoveredAssets.enumerated() {
            try await connectionTracker.ensureConnected()

            let contentHash = discovered.contentHashHint

            var masterAsset = try assetManager.createOrReuseMasterAsset(
                baseName: discovered.baseName,
                mediaType: discovered.mediaType,
                sourceKind: discovered.sourceKind,
                storageMode: discovered.suggestedStorageMode,
                sourceId: adapter.source.id,
                externalIdentifier: discovered.externalIdentifier,
                contentHash: contentHash,
                originalURL: discovered.suggestedStorageMode == .referenced
                    ? (discovered.previewFileURL ?? discovered.rawFileURL)
                    : nil,
                metadata: discovered.metadata
            )

            if !seenMasterAssetIds.insert(masterAsset.id).inserted {
                duplicateCount += 1
            }

            // Phase 1: Thumbnail
            let thumbnailURL = try AppDirectories.managedThumbnailURL(assetId: masterAsset.id)
            var thumbnailNeedsPersist = false
            if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
                let thumbSize = CGSize(
                    width: ThumbnailCache.thumbnailMaxPixelSize,
                    height: ThumbnailCache.thumbnailMaxPixelSize
                )
                if let thumbnail = try? await adapter.fetchThumbnail(discovered, size: thumbSize) {
                    try? Self.writeThumbnail(thumbnail, to: thumbnailURL)
                    masterAsset.thumbnailCacheURL = thumbnailURL
                    thumbnailNeedsPersist = true
                }
            } else if masterAsset.thumbnailCacheURL != thumbnailURL {
                masterAsset.thumbnailCacheURL = thumbnailURL
                thumbnailNeedsPersist = true
            }
            if thumbnailNeedsPersist {
                try assetManager.updateMasterAsset(masterAsset)
            }

            let expeditionAsset = try assetManager.addAssetToExpedition(
                assetId: masterAsset.id,
                expeditionId: expeditionId,
                addedBy: .importSession(sessionId.uuidString)
            )

            masterAssets.append(masterAsset)
            expeditionAssets.append(expeditionAsset)

            onProgress(ImportProgress(
                phase: .preparingThumbnails,
                completed: index + 1, total: total,
                currentItemName: discovered.baseName
            ))
        }

        // Phase 2: Copy previews
        for (index, discovered) in discoveredAssets.enumerated() {
            try await connectionTracker.ensureConnected()
            var masterAsset = masterAssets[index]

            if masterAsset.previewURL == nil || !Self.fileExistsAtURL(masterAsset.previewURL) {
                if discovered.suggestedStorageMode == .referenced {
                    if let previewURL = discovered.previewFileURL {
                        masterAsset.previewURL = previewURL
                        try assetManager.updateMasterAsset(masterAsset)
                        masterAssets[index] = masterAsset
                    }
                } else if let sourcePreviewURL = try await adapter.fetchPreview(discovered) {
                    let ext = sourcePreviewURL.pathExtension.isEmpty ? "jpg" : sourcePreviewURL.pathExtension
                    let destURL = try AppDirectories.managedPreviewURL(assetId: masterAsset.id, ext: ext)
                    try Self.atomicCopy(from: sourcePreviewURL, to: destURL)
                    masterAsset.previewURL = destURL
                    try assetManager.updateMasterAsset(masterAsset)
                    masterAssets[index] = masterAsset
                }
            }

            onProgress(ImportProgress(
                phase: .copyingPreviews,
                completed: index + 1, total: total,
                currentItemName: discovered.baseName
            ))
        }

        // Phase 3: Copy originals (managed only)
        for (index, discovered) in discoveredAssets.enumerated() {
            try await connectionTracker.ensureConnected()
            var masterAsset = masterAssets[index]

            if discovered.suggestedStorageMode == .referenced {
                var needsUpdate = false
                if masterAsset.rawURL == nil, let rawURL = discovered.rawFileURL {
                    masterAsset.rawURL = rawURL
                    needsUpdate = true
                }
                if masterAsset.originalURL == nil, let rawURL = discovered.rawFileURL {
                    masterAsset.originalURL = rawURL
                    needsUpdate = true
                }
                if masterAsset.livePhotoVideoURL == nil, let auxURL = discovered.auxiliaryFileURL {
                    masterAsset.livePhotoVideoURL = auxURL
                    needsUpdate = true
                }
                if needsUpdate {
                    try assetManager.updateMasterAsset(masterAsset)
                }
                masterAssets[index] = masterAsset
            } else {
                let needsRaw = masterAsset.rawURL == nil || !Self.fileExistsAtURL(masterAsset.rawURL)
                let needsAux = discovered.auxiliaryFileURL != nil
                    && (masterAsset.livePhotoVideoURL == nil || !Self.fileExistsAtURL(masterAsset.livePhotoVideoURL))

                if needsRaw, let sourceRawURL = try await adapter.fetchOriginal(discovered) {
                    let origDir = try AppDirectories.managedOriginalDirectory(assetId: masterAsset.id)
                    let destURL = origDir.appendingPathComponent(sourceRawURL.lastPathComponent)
                    try Self.atomicCopy(from: sourceRawURL, to: destURL)
                    masterAsset.rawURL = destURL
                    masterAsset.localManagedURL = destURL
                }

                if needsAux, let auxSourceURL = discovered.auxiliaryFileURL {
                    let origDir = try AppDirectories.managedOriginalDirectory(assetId: masterAsset.id)
                    let destURL = origDir.appendingPathComponent(auxSourceURL.lastPathComponent)
                    try Self.atomicCopy(from: auxSourceURL, to: destURL)
                    masterAsset.livePhotoVideoURL = destURL
                }

                if needsRaw || needsAux {
                    try assetManager.updateMasterAsset(masterAsset)
                    masterAssets[index] = masterAsset
                }
            }

            onProgress(ImportProgress(
                phase: .copyingOriginals,
                completed: index + 1, total: total,
                currentItemName: discovered.baseName
            ))
        }

        // Phase 4: Create ImportSession record
        let sessionRecord = ImportSessionRecord(
            id: sessionId.uuidString,
            sourceId: adapter.source.id.uuidString,
            targetExpeditionId: expeditionId.uuidString,
            startedAt: Date().timeIntervalSinceReferenceDate,
            completedAt: Date().timeIntervalSinceReferenceDate,
            status: "completed",
            totalItems: total,
            importedCount: total - duplicateCount,
            skippedCount: duplicateCount,
            failedItems: nil
        )
        try importSessionRepo.insert(sessionRecord)

        // Phase 5: Grouping → write PhotoGroup + PhotoGroupAsset records
        onProgress(ImportProgress(
            phase: .finalizing, completed: total, total: total,
            currentItemName: nil
        ))

        var seenIds = Set<UUID>()
        let uniqueAssets = masterAssets.filter { seenIds.insert($0.id).inserted }

        let v3Groups = await groupingEngine.makeGroupsFromMasterAssets(
            uniqueAssets, resolvesLocationNames: false
        )

        let now = Date().timeIntervalSinceReferenceDate
        for group in v3Groups {
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
                let assetRecord = PhotoGroupAssetRecord(
                    groupId: group.id.uuidString,
                    assetId: assetId.uuidString,
                    isRecommended: recommendedSet.contains(assetId)
                )
                try photoGroupRepo.addAsset(assetRecord)
            }
        }

        Self.logger.log(
            "Import completed: \(masterAssets.count) assets, \(duplicateCount) duplicates, \(v3Groups.count) groups"
        )

        return ImportResult(
            importedAssets: masterAssets,
            createdExpeditionAssets: expeditionAssets,
            duplicateCount: duplicateCount,
            groupCount: v3Groups.count,
            sessionId: sessionId
        )
    }

    // MARK: - Private Helpers

    private static func atomicCopy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let tempDest = destination.appendingPathExtension("importing")
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: tempDest.path) {
            try fm.removeItem(at: tempDest)
        }
        try fm.copyItem(at: source, to: tempDest)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempDest, to: destination)
    }

    private static func writeThumbnail(_ image: CGImage, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else {
            throw LumaError.persistenceFailed("无法创建缩略图缓存。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LumaError.persistenceFailed("无法写入缩略图缓存。")
        }
    }

    private static func fileExistsAtURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
