import AppKit
import CoreGraphics
import Foundation
@preconcurrency import Photos

/// 直接通过 PhotoKit 按 `localIdentifier` 拉取 NSImage，绕过磁盘缓存。
///
/// 用途：当导入时落盘的 preview 文件**不存在**（PhotoKit 返回 cloud-only 错误被吞）
/// 或**过小**（PhotoKit 返回了一份 displayVersion 缩略图）时，显示层有兜底机会
/// 直接从 Photos 数据库再问一次，能拿到多大就显示多大，不至于退化到 400px 缩略图。
///
/// 设计取舍：
/// - **不开网络**：和 `PhotosLibraryAdapter` 保持一致，`isNetworkAccessAllowed = false`，
///   避免后台不可控的 iCloud 下载。
/// - **`.highQualityFormat`**：等系统给出当前可用的最高分辨率版本（callback 只触发一次）。
/// - **`contentMode = .aspectFit`**：让 PhotoKit 按目标长边等比缩放，避免被裁。
/// - **`resizeMode = .exact`**：精确尺寸，避免被吐回去原图后还得自己 resize。
enum PhotosKitImageProvider {
    /// 拉取一张图，返回 `(image, pixelLongEdge)` 便于上层在多源之间挑最清楚的。
    /// `targetLongEdge` 单位是「pixels」（不是 points），调用方按 Retina 缩放预算自行换算。
    static func requestImage(localIdentifier: String, targetLongEdge: Int) async -> (NSImage, Int)? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            return nil
        }

        let target = CGSize(width: targetLongEdge, height: targetLongEdge)

        let image: NSImage? = await withCheckedContinuation { continuation in
            // 用 actor-free 状态守门，确保 continuation 只 resume 一次。
            // `.highQualityFormat` 文档说只回调一次，但保险起见兜一层避免任何意外重入。
            let resumed = ResumeGuard()

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.resizeMode = .exact
            options.isSynchronous = false
            options.version = .current

            PHImageManager.default().requestImage(
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

/// PhotoKit 回调可能在某些极端情况下被多次调用（虽然 `.highQualityFormat` 文档说只回调一次），
/// 这个 class 用 `NSLock` 保证 continuation 只 resume 一次。
/// `final class` + `Sendable`：内部加锁，可在 PhotoKit 后台线程安全访问。
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
