import AppKit
import Foundation

/// Unified image loading abstraction.
/// `LocalFileImageProvider` handles managed/referenced assets from disk.
/// `PhotoKitImageProvider` handles externalReference assets via PhotoKit.
protocol AssetImageProvider: Sendable {
    func thumbnail(for asset: MasterAsset, size: CGSize) async -> NSImage?
    func preview(for asset: MasterAsset, size: CGSize) async -> NSImage?
    func startPrefetch(assets: [MasterAsset], size: CGSize)
    func stopPrefetch(assets: [MasterAsset], size: CGSize)
}

/// Loads images from local file URLs (previewURL, thumbnailCacheURL, rawURL).
/// File I/O is dispatched off the main actor.
final class LocalFileImageProvider: AssetImageProvider {
    func thumbnail(for asset: MasterAsset, size: CGSize) async -> NSImage? {
        guard let url = asset.thumbnailCacheURL ?? asset.previewURL ?? asset.existingImageFileURL else {
            return nil
        }
        return await loadFromDisk(url)
    }

    func preview(for asset: MasterAsset, size: CGSize) async -> NSImage? {
        guard let url = asset.previewURL ?? asset.rawURL ?? asset.existingImageFileURL else {
            return nil
        }
        return await loadFromDisk(url)
    }

    func startPrefetch(assets: [MasterAsset], size: CGSize) {}
    func stopPrefetch(assets: [MasterAsset], size: CGSize) {}

    private func loadFromDisk(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
    }
}

/// Loads images via PhotoKit using the asset's externalIdentifier (PHAsset.localIdentifier).
/// Wraps `PhotosKitImageProvider` which uses `PHCachingImageManager` internally.
final class PhotoKitImageProvider: AssetImageProvider {
    func thumbnail(for asset: MasterAsset, size: CGSize) async -> NSImage? {
        await loadViaPhotoKit(asset: asset, size: size)
    }

    func preview(for asset: MasterAsset, size: CGSize) async -> NSImage? {
        await loadViaPhotoKit(asset: asset, size: size)
    }

    func startPrefetch(assets: [MasterAsset], size: CGSize) {
        let ids = assets.compactMap(\.externalIdentifier)
        guard !ids.isEmpty else { return }
        let targetEdge = Int(max(size.width, size.height))
        PhotosKitImageProvider.startPrefetch(localIdentifiers: ids, targetLongEdge: targetEdge)
    }

    func stopPrefetch(assets: [MasterAsset], size: CGSize) {
        let ids = assets.compactMap(\.externalIdentifier)
        guard !ids.isEmpty else { return }
        let targetEdge = Int(max(size.width, size.height))
        PhotosKitImageProvider.stopPrefetch(localIdentifiers: ids, targetLongEdge: targetEdge)
    }

    private func loadViaPhotoKit(asset: MasterAsset, size: CGSize) async -> NSImage? {
        guard let localId = asset.externalIdentifier else { return nil }
        let targetEdge = Int(max(size.width, size.height))
        guard let (image, _) = await PhotosKitImageProvider.requestImage(
            localIdentifier: localId, targetLongEdge: targetEdge
        ) else { return nil }
        return image
    }
}

/// Factory that returns the appropriate provider based on storage mode.
enum AssetImageProviderFactory {
    private static let localProvider = LocalFileImageProvider()
    private static let photoKitProvider = PhotoKitImageProvider()

    static func provider(for storageMode: AssetStorageMode) -> AssetImageProvider {
        switch storageMode {
        case .externalReference:
            return photoKitProvider
        case .managed, .referenced:
            return localProvider
        }
    }
}
