import CoreLocation
import Foundation
import Photos

struct PhotosAppExporter: ExportDestinationAdapter {
    var displayName: String {
        "照片 App"
    }

    func validateConfiguration(options: ExportOptions) async throws -> Bool {
        _ = options
        return true
    }

    func export(assets: [MediaAsset], groups: [PhotoGroup], options: ExportOptions) async throws -> ExportResult {
        let pickedAssets = assets.filter { asset in
            guard asset.userDecision == .picked else { return false }
            if let only = options.onlyAssetIDs { return only.contains(asset.id) }
            return true
        }

        // iCloud 闭环：按策略收集需要回删的原图（源 = 照片 App 且用户 reject）。
        let cleanupTargets: [MediaAsset] = {
            guard options.photosCleanupStrategy == .deleteRejectedOriginals else { return [] }
            return assets.filter { asset in
                guard asset.userDecision == .rejected else { return false }
                if case .photosLibrary(let id) = asset.source, !id.isEmpty { return true }
                return false
            }
        }()

        guard !pickedAssets.isEmpty || !cleanupTargets.isEmpty else {
            return ExportResult(exportedCount: 0, skippedCount: 0, destinationDescription: displayName)
        }

        let authorizationStatus = await authorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw authorizationError(for: authorizationStatus)
        }

        let groupLookup = Dictionary(
            groups.flatMap { group in group.assets.map { ($0, group.id) } },
            uniquingKeysWith: { first, _ in first }
        )

        // iCloud 闭环关键：source = .photosLibrary 的资产已在系统照片库里，按 localIdentifier 直接引用，
        // 避免 PHAssetCreationRequest 重复入库导致照片库里出现两份相同照片。
        var existingPHAssetByAssetID: [UUID: PHAsset] = [:]
        var newSourceAssets: [MediaAsset] = []
        var photosIdentifiers: [String] = []
        var assetIDByPhotosIdentifier: [String: UUID] = [:]

        for asset in pickedAssets {
            if case .photosLibrary(let identifier) = asset.source, !identifier.isEmpty {
                photosIdentifiers.append(identifier)
                assetIDByPhotosIdentifier[identifier] = asset.id
            } else {
                newSourceAssets.append(asset)
            }
        }

        if !photosIdentifiers.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: photosIdentifiers, options: nil)
            fetched.enumerateObjects { phAsset, _, _ in
                if let assetID = assetIDByPhotosIdentifier[phAsset.localIdentifier] {
                    existingPHAssetByAssetID[assetID] = phAsset
                }
            }
        }

        // 回删目标：按 localIdentifier 换成 PHAsset 引用。用户取消系统弹窗 → performChanges 返回 error，交由调用方处理。
        var cleanupPHAssets: [PHAsset] = []
        if !cleanupTargets.isEmpty {
            let cleanupIdentifiers = cleanupTargets.compactMap { asset -> String? in
                if case .photosLibrary(let id) = asset.source, !id.isEmpty { return id }
                return nil
            }
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: cleanupIdentifiers, options: nil)
            fetched.enumerateObjects { phAsset, _, _ in
                cleanupPHAssets.append(phAsset)
            }
        }

        // Dry-run 安全阀：options 里勾上「试跑」或 env LUMA_PHOTOS_CLEANUP_DRY_RUN=1，
        // 走完全流程但跳过 deleteAssets，只记录"将要删除 N 张"。
        let dryRunEnv = ProcessInfo.processInfo.environment["LUMA_PHOTOS_CLEANUP_DRY_RUN"] == "1"
        let dryRunCleanup = options.photosCleanupDryRun || dryRunEnv
        if !cleanupPHAssets.isEmpty {
            let ids = cleanupPHAssets.map(\.localIdentifier)
            RuntimeTrace.event(
                dryRunCleanup ? "photos_cleanup_dry_run" : "photos_cleanup_planned",
                category: "export",
                metadata: [
                    "count": "\(cleanupPHAssets.count)",
                    "strategy": options.photosCleanupStrategy.rawValue,
                    "dry_run": dryRunCleanup ? "1" : "0",
                    "local_identifiers_prefix": ids.prefix(5).joined(separator: ","),
                ]
            )
        }

        let plannedAssets = newSourceAssets.compactMap { asset -> PlannedAsset? in
            guard let stillPhoto = stillPhotoURL(for: asset, options: options) else {
                return nil
            }

            let resources = resources(for: asset, stillPhoto: stillPhoto, options: options)
            guard !resources.isEmpty else { return nil }

            let coordinate = asset.metadata.gpsCoordinate.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }

            return PlannedAsset(
                id: asset.id,
                groupID: groupLookup[asset.id],
                creationDate: asset.metadata.captureDate,
                location: coordinate,
                resources: resources
            )
        }

        let totalToProcess = plannedAssets.count + existingPHAssetByAssetID.count
        guard totalToProcess > 0 || !cleanupPHAssets.isEmpty else {
            throw LumaError.unsupported("当前 Picked 素材里没有可写入照片 App 的源文件。")
        }

        let existingAlbumsByGroupID = existingAlbums(for: groups)

        let photoLibrary = PHPhotoLibrary.shared()

        // Stage 1：创建新资产 + 构建相册（picked 入相册）。这一阶段不涉及删除，用户不会看到弹窗，必成功。
        try await performChanges(in: photoLibrary) {
            var placeholdersByAssetID: [UUID: PHObjectPlaceholder] = [:]

            for plannedAsset in plannedAssets {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.creationDate = plannedAsset.creationDate
                creationRequest.location = plannedAsset.location

                for resource in plannedAsset.resources {
                    creationRequest.addResource(
                        with: resource.type,
                        fileURL: resource.url,
                        options: resource.creationOptions
                    )
                }

                if let placeholder = creationRequest.placeholderForCreatedAsset {
                    placeholdersByAssetID[plannedAsset.id] = placeholder
                }
            }

            guard options.createAlbumPerGroup else { return }

            for group in groups {
                let memberRefs: [Any] = group.assets.compactMap { assetID -> Any? in
                    if let phAsset = existingPHAssetByAssetID[assetID] {
                        return phAsset
                    }
                    if let placeholder = placeholdersByAssetID[assetID] {
                        return placeholder
                    }
                    return nil
                }

                guard !memberRefs.isEmpty else { continue }

                if let existingAlbum = existingAlbumsByGroupID[group.id] {
                    let changeRequest = PHAssetCollectionChangeRequest(for: existingAlbum)
                    changeRequest?.addAssets(memberRefs as NSArray)
                } else {
                    let collectionRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                        withTitle: sanitizedAlbumTitle(for: group)
                    )
                    collectionRequest.addAssets(memberRefs as NSArray)
                }
            }
        }

        // Stage 2：清理未选原图。独立 performChanges，用户取消只回滚"删除"，不会连带回滚 Stage 1 的相册。
        var actuallyCleanedCount = 0
        var cleanupCancelledCount = 0
        if !cleanupPHAssets.isEmpty, !dryRunCleanup {
            do {
                try await performChanges(in: photoLibrary) {
                    PHAssetChangeRequest.deleteAssets(cleanupPHAssets as NSArray)
                }
                actuallyCleanedCount = cleanupPHAssets.count
                RuntimeTrace.event(
                    "photos_cleanup_committed",
                    category: "export",
                    metadata: ["count": "\(cleanupPHAssets.count)"]
                )
            } catch LumaError.userCancelled {
                cleanupCancelledCount = cleanupPHAssets.count
                RuntimeTrace.event(
                    "photos_cleanup_cancelled_by_user",
                    category: "export",
                    metadata: ["declined_count": "\(cleanupPHAssets.count)"]
                )
            }
        } else if !cleanupPHAssets.isEmpty, dryRunCleanup {
            // Dry-run：相册已建，仅回报"本会删除"的数量，不实际调用 PhotoKit。
            actuallyCleanedCount = cleanupPHAssets.count
        }

        // 摘要相册描述：按分组建子相册时给"X 个分组相册"，否则给单一相册名（默认按 Session 名）。
        let albumDescription: String
        if options.createAlbumPerGroup, !groups.isEmpty {
            albumDescription = "\(groups.count) 个分组相册"
        } else {
            albumDescription = "Photos · \(displayName)"
        }

        return ExportResult(
            exportedCount: totalToProcess,
            skippedCount: max(0, pickedAssets.count - totalToProcess),
            destinationDescription: displayName,
            cleanedCount: actuallyCleanedCount,
            cleanupCancelledCount: cleanupCancelledCount,
            failures: [],
            albumDescription: albumDescription,
            destinationURL: nil
        )
    }

    private func authorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func performChanges(in photoLibrary: PHPhotoLibrary, changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            photoLibrary.performChanges(changes) { success, error in
                if let error {
                    // 用户在系统原生「删除确认」对话框点「不删除」→ NSUserCancelledError (3072)。
                    // 不是真错误，翻成 .userCancelled 让上层按取消处理；整批 performChanges 已回滚，
                    // 相册也不会被创建，照片库保持原样。
                    let ns = error as NSError
                    if ns.code == NSUserCancelledError
                        || (ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError)
                        || (ns.domain == "PHPhotosErrorDomain" && ns.code == 3072) {
                        continuation.resume(throwing: LumaError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: LumaError.persistenceFailed("Photos App 导出失败。"))
                }
            }
        }
    }

    private func stillPhotoURL(for asset: MediaAsset, options: ExportOptions) -> URL? {
        if options.preserveLivePhoto, asset.livePhotoVideoURL != nil {
            return asset.previewURL ?? asset.rawURL
        }

        if options.mergeRawAndJpeg,
           let rawURL = asset.rawURL,
           asset.previewURL != nil {
            return rawURL
        }

        return asset.previewURL ?? asset.rawURL
    }

    private func resources(for asset: MediaAsset, stillPhoto: URL, options: ExportOptions) -> [PlannedResource] {
        var resources: [PlannedResource] = [
            PlannedResource(type: .photo, url: stillPhoto)
        ]

        if options.preserveLivePhoto,
           let liveVideoURL = asset.livePhotoVideoURL {
            resources.append(PlannedResource(type: .pairedVideo, url: liveVideoURL))
            return resources
        }

        if options.mergeRawAndJpeg,
           let rawURL = asset.rawURL,
           let previewURL = asset.previewURL,
           rawURL != previewURL {
            resources = [
                PlannedResource(type: .photo, url: rawURL),
                PlannedResource(type: .alternatePhoto, url: previewURL),
            ]
        }

        return resources
    }

    private func sanitizedAlbumTitle(for group: PhotoGroup) -> String {
        AppDirectories.sanitizePathComponent(group.name)
    }

    private func existingAlbums(for groups: [PhotoGroup]) -> [UUID: PHAssetCollection] {
        var result: [UUID: PHAssetCollection] = [:]

        for group in groups {
            let title = sanitizedAlbumTitle(for: group)
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "localizedTitle == %@", title)
            options.fetchLimit = 1

            let fetchResult = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .albumRegular,
                options: options
            )

            if let collection = fetchResult.firstObject {
                result[group.id] = collection
            }
        }

        return result
    }

    private func authorizationError(for status: PHAuthorizationStatus) -> LumaError {
        switch status {
        case .denied, .restricted:
            return .unsupported("没有 Photos 写入权限，请在系统设置里允许 Luma 访问“照片”。")
        case .limited:
            return .unsupported("当前 Photos 权限受限，无法完成导出。请在系统设置里将 Luma 调整为完全访问。")
        case .notDetermined:
            return .unsupported("尚未获得 Photos 写入权限。")
        case .authorized:
            return .unsupported("Photos 写入权限状态异常。")
        @unknown default:
            return .unsupported("无法识别的 Photos 权限状态。")
        }
    }
}

private struct PlannedAsset {
    let id: UUID
    let groupID: UUID?
    let creationDate: Date
    let location: CLLocation?
    let resources: [PlannedResource]
}

private struct PlannedResource {
    let type: PHAssetResourceType
    let url: URL

    var creationOptions: PHAssetResourceCreationOptions {
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = url.lastPathComponent
        return options
    }
}
