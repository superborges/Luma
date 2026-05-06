import Foundation
@preconcurrency import Photos

/// Production implementation backed by real PhotoKit APIs.
final class SystemPhotoLibraryProvider: PhotoLibraryProvider, @unchecked Sendable {

    func currentAuthorizationStatus() -> PhotoAuthorizationStatus {
        mapStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotoAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return mapStatus(status)
    }

    func enumerateAssets() async -> [PHAssetSnapshot] {
        await PhotoKitSafetyWrapper.withTimeout(120, fallback: []) {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let result = PHAsset.fetchAssets(with: options)
            var snapshots: [PHAssetSnapshot] = []
            snapshots.reserveCapacity(result.count)

            result.enumerateObjects { asset, _, _ in
                let isLocal = Self.checkLocalAvailability(asset)
                snapshots.append(PHAssetSnapshot(
                    localIdentifier: asset.localIdentifier,
                    mediaType: .photo,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationDate: asset.creationDate,
                    modificationDate: asset.modificationDate,
                    latitude: asset.location?.coordinate.latitude,
                    longitude: asset.location?.coordinate.longitude,
                    isFavorite: asset.isFavorite,
                    isLocallyAvailable: isLocal
                ))
            }
            return snapshots
        }
    }

    func fetchCollections() async -> [PHCollectionSnapshot] {
        await PhotoKitSafetyWrapper.withTimeout(10, fallback: []) {
            var results: [PHCollectionSnapshot] = []

            let smartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .any, options: nil
            )
            smartAlbums.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle, !title.isEmpty else { return }
                results.append(PHCollectionSnapshot(
                    localIdentifier: collection.localIdentifier,
                    title: title,
                    estimatedAssetCount: collection.estimatedAssetCount,
                    collectionType: .smartAlbum
                ))
            }

            let userAlbums = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: nil
            )
            userAlbums.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle, !title.isEmpty else { return }
                results.append(PHCollectionSnapshot(
                    localIdentifier: collection.localIdentifier,
                    title: title,
                    estimatedAssetCount: collection.estimatedAssetCount,
                    collectionType: .userAlbum
                ))
            }
            return results
        }
    }

    func assetIdentifiers(in collectionId: String) async -> [String] {
        await PhotoKitSafetyWrapper.withTimeout(10, fallback: []) {
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [collectionId], options: nil
            )
            guard let collection = collections.firstObject else { return [] }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            var ids: [String] = []
            ids.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                ids.append(asset.localIdentifier)
            }
            return ids
        }
    }

    // MARK: - Helpers

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotoAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    private static func checkLocalAvailability(_ asset: PHAsset) -> Bool {
        asset.sourceType.contains(.typeUserLibrary)
    }
}
