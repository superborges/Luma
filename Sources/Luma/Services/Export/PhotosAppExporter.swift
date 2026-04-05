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
        let pickedAssets = assets.filter { $0.userDecision == .picked }
        guard !pickedAssets.isEmpty else {
            return ExportResult(exportedCount: 0, skippedCount: 0, destinationDescription: displayName)
        }

        let authorizationStatus = await authorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw authorizationError(for: authorizationStatus)
        }

        let groupLookup = Dictionary(uniqueKeysWithValues: groups.flatMap { group in
            group.assets.map { ($0, group.id) }
        })

        let plannedAssets = pickedAssets.compactMap { asset -> PlannedAsset? in
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

        guard !plannedAssets.isEmpty else {
            throw LumaError.unsupported("当前 Picked 素材里没有可写入照片 App 的源文件。")
        }

        let existingAlbumsByGroupID = existingAlbums(for: groups)

        let photoLibrary = PHPhotoLibrary.shared()
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
                let placeholders = plannedAssets
                    .filter { $0.groupID == group.id }
                    .compactMap { placeholdersByAssetID[$0.id] }

                guard !placeholders.isEmpty else { continue }

                if let existingAlbum = existingAlbumsByGroupID[group.id] {
                    let changeRequest = PHAssetCollectionChangeRequest(for: existingAlbum)
                    changeRequest?.addAssets(placeholders as NSArray)
                } else {
                    let collectionRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                        withTitle: sanitizedAlbumTitle(for: group)
                    )
                    collectionRequest.addAssets(placeholders as NSArray)
                }
            }
        }

        return ExportResult(
            exportedCount: plannedAssets.count,
            skippedCount: max(0, pickedAssets.count - plannedAssets.count),
            destinationDescription: displayName
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
                    continuation.resume(throwing: error)
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
