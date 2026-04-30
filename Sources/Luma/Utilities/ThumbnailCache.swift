import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private var cachedKeys: Set<String> = []
    private var inflightLoads: [String: Task<NSImage?, Never>] = [:]
    private var lastPreheatSignature: String?
    private var memoryHits = 0
    private var diskHits = 0
    private var inflightJoins = 0
    private var generatedImages = 0
    private var preheatedItems = 0
    private var trimEvictions = 0

    /// Retina 2x 显示下右栏 3 列网格每格约 110pt = 220px；
    /// 600px 确保即使 3x 缩放或大尺寸屏幕也能保持清晰。
    nonisolated static let thumbnailMaxPixelSize = 600

    init(countLimit: Int = 800) {
        memoryCache.countLimit = countLimit
    }

    func updateCountLimit(_ limit: Int) {
        memoryCache.countLimit = limit
    }

    func image(for asset: MediaAsset) async -> NSImage? {
        let key = asset.id.uuidString
        if let cached = memoryImage(forKey: key) {
            return cached
        }

        if let inflight = inflightLoads[key] {
            inflightJoins += 1
            return await inflight.value
        }

        return await startLoad(for: asset, key: key).value
    }

    func preheat(assets: [MediaAsset]) {
        for asset in assets {
            let key = asset.id.uuidString
            if memoryImage(forKey: key) != nil || inflightLoads[key] != nil {
                continue
            }

            preheatedItems += 1
            _ = startLoad(for: asset, key: key)
        }
    }

    func preheatNeighborhood(around assetID: UUID, in assets: [MediaAsset], radius: Int = 18) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }

        let lowerBound = max(assets.startIndex, index - radius)
        let upperBound = min(assets.endIndex, index + radius + 1)
        let neighborhood = Array(assets[lowerBound..<upperBound])
        let signature = "\(neighborhood.first?.id.uuidString ?? "start")-\(neighborhood.last?.id.uuidString ?? "end")-\(neighborhood.count)"

        guard signature != lastPreheatSignature else { return }
        lastPreheatSignature = signature
        preheat(assets: neighborhood)
    }

    func trim(toRetainAssetIDs retainedAssetIDs: Set<UUID>) {
        let retainedKeys = Set(retainedAssetIDs.map(\.uuidString))

        for key in cachedKeys.subtracting(retainedKeys) {
            memoryCache.removeObject(forKey: key as NSString)
            cachedKeys.remove(key)
            trimEvictions += 1
        }

        for key in inflightLoads.keys where !retainedKeys.contains(key) {
            inflightLoads[key]?.cancel()
            inflightLoads.removeValue(forKey: key)
        }
    }

    func invalidateAll() {
        inflightLoads.values.forEach { $0.cancel() }
        inflightLoads.removeAll()
        memoryCache.removeAllObjects()
        cachedKeys.removeAll()
        lastPreheatSignature = nil
    }

    func snapshot() -> ThumbnailCacheSnapshot {
        ThumbnailCacheSnapshot(
            memoryHits: memoryHits,
            diskHits: diskHits,
            inflightJoins: inflightJoins,
            generatedImages: generatedImages,
            preheatedItems: preheatedItems,
            trimEvictions: trimEvictions,
            activeMemoryItems: cachedKeys.count,
            inflightLoads: inflightLoads.count
        )
    }

    func resetDiagnostics() {
        memoryHits = 0
        diskHits = 0
        inflightJoins = 0
        generatedImages = 0
        preheatedItems = 0
        trimEvictions = 0
    }

    private func memoryImage(forKey key: String) -> NSImage? {
        let cacheKey = key as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            memoryHits += 1
            return cached
        }
        return nil
    }

    @discardableResult
    private func startLoad(for asset: MediaAsset, key: String) -> Task<NSImage?, Never> {
        if let existing = inflightLoads[key] {
            return existing
        }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.loadImage(for: asset, key: key)
            _ = await MainActor.run {
                self.inflightLoads.removeValue(forKey: key)
            }
            return image
        }

        inflightLoads[key] = task
        return task
    }

    private func loadImage(for asset: MediaAsset, key: String) async -> NSImage? {
        if let cached = memoryImage(forKey: key) {
            return cached
        }

        guard let thumbnailURL = asset.thumbnailURL else {
            return nil
        }

        // 依次尝试 preview → raw 作为生成源（与 DisplayImageCache 策略一致）
        let candidates = [asset.previewURL, asset.rawURL].compactMap { $0 }
        var payload: ThumbnailPayload?
        for source in candidates where payload == nil {
            payload = await Self.loadThumbnailPayload(
                from: source,
                thumbnailURL: thumbnailURL,
                maxPixelSize: Self.thumbnailMaxPixelSize
            )
        }

        guard let payload else {
            return nil
        }

        guard !Task.isCancelled else { return nil }

        let rep = NSBitmapImageRep(cgImage: payload.cgImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)

        memoryCache.setObject(image, forKey: key as NSString)
        cachedKeys.insert(key)
        switch payload.origin {
        case .disk:
            diskHits += 1
        case .generated:
            generatedImages += 1
        }
        return image
    }

    /// 磁盘缓存版本。旧版本（无后缀）的 PNG 可能因 ImageIO orientation bug 导致方向错误，
    /// 加版本后缀让旧文件自动失效、触发重新生成。
    private nonisolated static let diskCacheVersion = 4

    private nonisolated static func versionedURL(_ thumbnailURL: URL) -> URL {
        let base = thumbnailURL.deletingPathExtension().lastPathComponent
        return thumbnailURL.deletingLastPathComponent()
            .appendingPathComponent("\(base)@\(diskCacheVersion).png")
    }

    private nonisolated static func loadThumbnailPayload(
        from sourceURL: URL,
        thumbnailURL: URL,
        maxPixelSize: Int
    ) async -> ThumbnailPayload? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let vURL = versionedURL(thumbnailURL)

                // 1. 优先读取版本化磁盘缓存
                if let image = decodeImage(at: vURL) {
                    continuation.resume(returning: ThumbnailPayload(cgImage: image, origin: .disk))
                    return
                }

                // 2. 从 source 文件重新生成
                if let image = generateThumbnail(
                    from: sourceURL,
                    to: vURL,
                    maxPixelSize: maxPixelSize
                ) {
                    continuation.resume(returning: ThumbnailPayload(cgImage: image, origin: .generated))
                    return
                }

                // 3. Fallback: 读取导入时生成的原始缩略图（可能方向不对但至少有内容）
                if let image = decodeImage(at: thumbnailURL) {
                    continuation.resume(returning: ThumbnailPayload(cgImage: image, origin: .disk))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private nonisolated static func decodeImage(at url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static func generateThumbnail(
        from sourceURL: URL,
        to destinationURL: URL,
        maxPixelSize: Int
    ) -> CGImage? {
        guard let cgImage = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: maxPixelSize) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return cgImage
    }
}

private struct ThumbnailPayload: @unchecked Sendable {
    let cgImage: CGImage
    let origin: ThumbnailLoadOrigin
}

private enum ThumbnailLoadOrigin: Sendable {
    case disk
    case generated
}
