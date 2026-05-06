import AppKit
import CoreGraphics
import Foundation
@preconcurrency import Photos

/// 通过 `PHCachingImageManager` 拉取 Mac Photos 图库中的图片。
///
/// 使用 `PHCachingImageManager` 而非 `PHImageManager.default()`，
/// 支持预取（prefetch）缩略图，大幅提升大图库滚动时的加载速度。
///
/// 设计取舍：
/// - **不开网络**：`isNetworkAccessAllowed = false`，避免后台 iCloud 下载。
/// - **`.highQualityFormat`**：等系统给出当前可用的最高分辨率版本。
/// - **`contentMode = .aspectFit`**：等比缩放，避免裁切。
/// - **`resizeMode = .exact`**：精确尺寸。
enum PhotosKitImageProvider {

    private static let cachingManager: PHCachingImageManager = {
        let mgr = PHCachingImageManager()
        mgr.allowsCachingHighQualityImages = false
        return mgr
    }()

    /// 拉取一张图，返回 `(image, pixelLongEdge)` 便于上层在多源之间挑最清楚的。
    /// `targetLongEdge` 单位是「pixels」（不是 points），调用方按 Retina 缩放预算自行换算。
    static func requestImage(localIdentifier: String, targetLongEdge: Int) async -> (NSImage, Int)? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            return nil
        }

        let target = CGSize(width: targetLongEdge, height: targetLongEdge)

        let image: NSImage? = await withCheckedContinuation { continuation in
            let resumed = ResumeGuard()

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.resizeMode = .exact
            options.isSynchronous = false
            options.version = .current

            cachingManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if resumed.fire() {
                    continuation.resume(returning: image)
                }
            }
        }

        guard let image else { return nil }
        let rep = image.representations.first as? NSBitmapImageRep
        let pixelLongEdge = rep.map { max($0.pixelsWide, $0.pixelsHigh) } ?? Int(max(image.size.width, image.size.height))
        return (image, pixelLongEdge)
    }

    // MARK: - Prefetch (PHCachingImageManager)

    /// 预取一批 PHAsset 的缩略图到内存缓存，提升后续 `requestImage` 的命中速度。
    static func startPrefetch(localIdentifiers: [String], targetLongEdge: Int) {
        guard let (assets, target, options) = prefetchParams(localIdentifiers: localIdentifiers, targetLongEdge: targetLongEdge) else { return }
        cachingManager.startCachingImages(for: assets, targetSize: target, contentMode: .aspectFit, options: options)
    }

    /// 取消预取，释放缓存资源。
    static func stopPrefetch(localIdentifiers: [String], targetLongEdge: Int) {
        guard let (assets, target, options) = prefetchParams(localIdentifiers: localIdentifiers, targetLongEdge: targetLongEdge) else { return }
        cachingManager.stopCachingImages(for: assets, targetSize: target, contentMode: .aspectFit, options: options)
    }

    private static func prefetchParams(localIdentifiers: [String], targetLongEdge: Int) -> ([PHAsset], CGSize, PHImageRequestOptions)? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard fetchResult.count > 0 else { return nil }
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        let target = CGSize(width: targetLongEdge, height: targetLongEdge)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.resizeMode = .exact
        return (assets, target, options)
    }
}

extension MediaAsset {
    /// 若是 `.photosLibrary` 来源，返回 PHAsset 的 localIdentifier；否则 nil。
    /// 显示层用它判断是否能走 PhotoKit fallback。
    var photosLibraryLocalIdentifier: String? {
        if case let .photosLibrary(identifier) = source {
            return identifier
        }
        return nil
    }
}

/// PhotoKit 回调可能在某些极端情况下被多次调用，
/// 这个 class 用 `NSLock` 保证 continuation 只 resume 一次。
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
