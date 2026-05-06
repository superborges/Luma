import CoreLocation
import Foundation
import Photos

struct PhotosAlbumSyncAdapter: AlbumSyncAdapter {
    var displayName: String { "Photos" }

    func createAlbum(name: String, assets: [MasterAsset]) async throws -> ExternalAlbumRef {
        try await ensureAuthorized()

        var collectionPlaceholder: PHObjectPlaceholder?
        let (existingByAssetId, localFileAssets) = partitionAssets(assets)

        try await performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            collectionPlaceholder = request.placeholderForCreatedAssetCollection

            var memberRefs: [Any] = []

            for asset in assets {
                if let phAsset = existingByAssetId[asset.id] {
                    memberRefs.append(phAsset)
                }
            }

            let createdPlaceholders = Self.createPHAssets(for: localFileAssets)
            memberRefs.append(contentsOf: createdPlaceholders)

            if !memberRefs.isEmpty {
                request.addAssets(memberRefs as NSArray)
            }
        }

        guard let placeholder = collectionPlaceholder else {
            throw LumaError.persistenceFailed("Failed to obtain placeholder for created Photos album")
        }

        let albumId = UUID()
        return ExternalAlbumRef(
            provider: .macPhotos,
            localIdentifier: placeholder.localIdentifier,
            albumId: albumId
        )
    }

    func updateAlbum(_ ref: ExternalAlbumRef, assets: [MasterAsset]) async throws {
        try await ensureAuthorized()

        guard let collection = fetchCollection(ref.localIdentifier) else {
            throw LumaError.persistenceFailed("Photos album not found: \(ref.localIdentifier)")
        }

        let existingAssetIds = fetchExistingAssetIds(in: collection)
        let (existingByAssetId, localFileAssets) = partitionAssets(assets)

        let newPhotosAssets = existingByAssetId.filter { !existingAssetIds.contains($0.value.localIdentifier) }

        guard !newPhotosAssets.isEmpty || !localFileAssets.isEmpty else { return }

        try await performChanges {
            guard let changeRequest = PHAssetCollectionChangeRequest(for: collection) else { return }

            var memberRefs: [Any] = []
            for (_, phAsset) in newPhotosAssets {
                memberRefs.append(phAsset)
            }

            let createdPlaceholders = Self.createPHAssets(for: localFileAssets)
            memberRefs.append(contentsOf: createdPlaceholders)

            if !memberRefs.isEmpty {
                changeRequest.addAssets(memberRefs as NSArray)
            }
        }
    }

    func removeAssets(_ assets: [MasterAsset], from ref: ExternalAlbumRef) async throws {
        try await ensureAuthorized()

        guard let collection = fetchCollection(ref.localIdentifier) else {
            throw LumaError.persistenceFailed("Photos album not found: \(ref.localIdentifier)")
        }

        let identifiers = assets.compactMap(\.externalIdentifier).filter { !$0.isEmpty }
        let localURLAssets = assets.filter {
            $0.storageMode != .externalReference && ($0.previewURL != nil || $0.rawURL != nil)
        }

        var phAssetsToRemove: [PHAsset] = []

        if !identifiers.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            fetched.enumerateObjects { phAsset, _, _ in
                phAssetsToRemove.append(phAsset)
            }
        }

        let collectionAssets = fetchCollectionAssets(in: collection)
        for asset in localURLAssets {
            let baseName = asset.baseName.lowercased()
            for phAsset in collectionAssets {
                let resources = PHAssetResource.assetResources(for: phAsset)
                if resources.contains(where: { $0.originalFilename.lowercased().hasPrefix(baseName) }) {
                    phAssetsToRemove.append(phAsset)
                    break
                }
            }
        }

        guard !phAssetsToRemove.isEmpty else { return }

        try await performChanges {
            guard let changeRequest = PHAssetCollectionChangeRequest(for: collection) else { return }
            changeRequest.removeAssets(phAssetsToRemove as NSArray)
        }
    }

    func validateAccess(_ ref: ExternalAlbumRef) async throws -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }
        return fetchCollection(ref.localIdentifier) != nil
    }

    // MARK: - Private Helpers

    private func ensureAuthorized() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                    continuation.resume(returning: s)
                }
            }
        }
        guard status == .authorized || status == .limited else {
            throw LumaError.unsupported("没有 Photos 写入权限，请在系统设置里允许 Luma 访问「照片」。")
        }
    }

    private func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
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
                    continuation.resume(throwing: LumaError.persistenceFailed("Photos album sync failed"))
                }
            }
        }
    }

    private func partitionAssets(_ assets: [MasterAsset]) -> (existingByAssetId: [UUID: PHAsset], localFileAssets: [MasterAsset]) {
        var existingByAssetId: [UUID: PHAsset] = [:]
        var localFileAssets: [MasterAsset] = []

        var photosIdentifiers: [String] = []
        var assetIdByIdentifier: [String: UUID] = [:]

        for asset in assets {
            if asset.storageMode == .externalReference,
               let identifier = asset.externalIdentifier, !identifier.isEmpty {
                photosIdentifiers.append(identifier)
                assetIdByIdentifier[identifier] = asset.id
            } else if asset.previewURL != nil || asset.rawURL != nil {
                localFileAssets.append(asset)
            }
        }

        if !photosIdentifiers.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: photosIdentifiers, options: nil)
            fetched.enumerateObjects { phAsset, _, _ in
                if let assetId = assetIdByIdentifier[phAsset.localIdentifier] {
                    existingByAssetId[assetId] = phAsset
                }
            }
        }

        return (existingByAssetId, localFileAssets)
    }

    private static func createPHAssets(for assets: [MasterAsset]) -> [PHObjectPlaceholder] {
        var placeholders: [PHObjectPlaceholder] = []
        for asset in assets {
            guard let fileURL = asset.previewURL ?? asset.rawURL else { continue }
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.creationDate = asset.captureDate

            if let coord = asset.metadata?.gpsCoordinate {
                creationRequest.location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            }

            let options = PHAssetResourceCreationOptions()
            options.originalFilename = fileURL.lastPathComponent
            creationRequest.addResource(with: .photo, fileURL: fileURL, options: options)

            if let placeholder = creationRequest.placeholderForCreatedAsset {
                placeholders.append(placeholder)
            }
        }
        return placeholders
    }

    private func fetchCollection(_ localIdentifier: String) -> PHAssetCollection? {
        let result = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        return result.firstObject
    }

    private func fetchExistingAssetIds(in collection: PHAssetCollection) -> Set<String> {
        let result = PHAsset.fetchAssets(in: collection, options: nil)
        var ids = Set<String>()
        result.enumerateObjects { asset, _, _ in
            ids.insert(asset.localIdentifier)
        }
        return ids
    }

    private func fetchCollectionAssets(in collection: PHAssetCollection) -> [PHAsset] {
        let result = PHAsset.fetchAssets(in: collection, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}
