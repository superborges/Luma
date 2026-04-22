import AppKit
import Foundation

@MainActor
final class DisplayImageCache {
    static let shared = DisplayImageCache()

    /// 解码策略或 key 格式变更时递增，避免内存里长期命中旧缓存导致中央大图发糊。
    private static let cacheKeySchema = "display:v4"

    private let memoryCache = NSCache<NSString, NSImage>()
    private var cachedKeys: Set<String> = []
    private var inflightLoads: [String: Task<NSImage?, Never>] = [:]
    private var lastPreheatSignature: String?
    private var memoryHits = 0
    private var inflightJoins = 0
    private var decodedImages = 0
    private var preheatedItems = 0
    private var trimEvictions = 0

    private init() {
        memoryCache.countLimit = 16
    }

    func cachedImage(for asset: MediaAsset) -> NSImage? {
        memoryImage(forKey: Self.cacheKey(for: asset.id))
    }

    func image(for asset: MediaAsset) async -> NSImage? {
        let key = Self.cacheKey(for: asset.id)
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
            let key = Self.cacheKey(for: asset.id)
            if memoryCache.object(forKey: key as NSString) != nil || inflightLoads[key] != nil {
                continue
            }
            preheatedItems += 1
            _ = startLoad(for: asset, key: key)
        }
    }

    func preheatNeighborhood(around assetID: UUID, in assets: [MediaAsset], radius: Int = 2) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }

        let lowerBound = max(assets.startIndex, index - radius)
        let upperBound = min(assets.endIndex, index + radius + 1)
        let neighborhood = Array(assets[lowerBound..<upperBound])
        let signature = "\(neighborhood.first?.id.uuidString ?? "start")-\(neighborhood.last?.id.uuidString ?? "end")-\(neighborhood.count)"

        guard signature != lastPreheatSignature else { return }
        lastPreheatSignature = signature
        preheat(assets: neighborhood)
        trim(toRetainAssetIDs: Set(neighborhood.map(\.id)))
    }

    func trim(toRetainAssetIDs retainedAssetIDs: Set<UUID>) {
        let retainedKeys = Set(retainedAssetIDs.map { Self.cacheKey(for: $0) })

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

    func snapshot() -> DisplayImageCacheSnapshot {
        DisplayImageCacheSnapshot(
            memoryHits: memoryHits,
            inflightJoins: inflightJoins,
            decodedImages: decodedImages,
            preheatedItems: preheatedItems,
            trimEvictions: trimEvictions,
            activeMemoryItems: cachedKeys.count,
            inflightLoads: inflightLoads.count
        )
    }

    func resetDiagnostics() {
        memoryHits = 0
        inflightJoins = 0
        decodedImages = 0
        preheatedItems = 0
        trimEvictions = 0
    }

    private static func cacheKey(for assetID: UUID) -> String {
        "\(assetID.uuidString)@\(cacheKeySchema)"
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

        let maxPixelSize = recommendedMaxPixelSize(for: asset)
        let preview = asset.previewURL
        let raw = asset.rawURL
        let thumb = asset.thumbnailURL
        let photosLibraryID = asset.photosLibraryLocalIdentifier
        // PhotoKit 兜底「足够清晰」的目标长边：当 disk 解码出来的图比这个还小，就再问一次。
        let satisfactoryLongEdge = max(maxPixelSize / 2, 1600)

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            // 先分别解码 preview（若有）与 raw（若有且不同），取「像素长边更大」的图；
            // 导入管线里 preview 往往是一张小 JPEG，raw 才是清晰原图——若「首个成功就停」会一直用糊图。
            var best: (NSImage, Int)? = nil
            if let p = preview {
                if let decoded = await Self.decodeDisplayImage(from: p, maxPixelSize: maxPixelSize) {
                    best = decoded
                }
            }
            if let r = raw, r != preview {
                if let decoded = await Self.decodeDisplayImage(from: r, maxPixelSize: maxPixelSize) {
                    if best == nil || decoded.1 > best!.1 {
                        best = decoded
                    }
                }
            }

            // PhotoKit 兜底：disk 拿不到图（preview/raw 文件缺失），或拿到的图明显太小（preview 是 displayVersion
            // 之类的 1080 缩略图）。直接按 PHAsset.localIdentifier 再问一次系统，要多大给多大。
            // 只在 source 是 .photosLibrary 时启用——其他来源（SD 卡 / iPhone / 文件夹）没有 localIdentifier。
            if let photosLibraryID,
               (best == nil || best!.1 < satisfactoryLongEdge) {
                if let phImage = await PhotosKitImageProvider.requestImage(
                    localIdentifier: photosLibraryID,
                    targetLongEdge: maxPixelSize
                ) {
                    if best == nil || phImage.1 > best!.1 {
                        best = phImage
                    }
                }
            }

            // 最后一道兜底：本地 thumbnail PNG（400px 左右），保证至少能显示出来。
            if best == nil, let t = thumb, t != preview, t != raw {
                if let decoded = await Self.decodeDisplayImage(from: t, maxPixelSize: min(maxPixelSize, 2048)) {
                    best = decoded
                }
            }
            let image = best?.0
            _ = await MainActor.run {
                self.inflightLoads.removeValue(forKey: key)
                if let image {
                    self.memoryCache.setObject(image, forKey: key as NSString)
                    self.cachedKeys.insert(key)
                    self.decodedImages += 1
                }
            }
            return image
        }

        inflightLoads[key] = task
        return task
    }

    /// 返回 `(NSImage, 像素长边)`，便于在 preview / raw 之间选更清晰的。
    /// CGImage 在后台解码；`NSImage` 在主线程用 `NSBitmapImageRep` 挂接，避免 Retina 下糊成一团。
    private nonisolated static func decodeDisplayImage(from sourceURL: URL, maxPixelSize: Int) async -> (NSImage, Int)? {
        let cgImage = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let cg = EXIFParser.cgImageForDisplay(at: sourceURL, maxLongEdge: maxPixelSize)
                continuation.resume(returning: cg)
            }
        }
        guard let cgImage else { return nil }
        let longEdge = max(cgImage.width, cgImage.height)
        let image = await MainActor.run {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let img = NSImage(size: rep.size)
            img.addRepresentation(rep)
            return img
        }
        return (image, longEdge)
    }

    /// Retina 大屏：长边至少给到「足够清晰」的像素预算；上限 4096 控制内存。
    private func recommendedMaxPixelSize(for asset: MediaAsset) -> Int {
        let sourceMax = max(asset.metadata.imageWidth, asset.metadata.imageHeight)
        if sourceMax > 0 {
            return min(max(sourceMax, 2560), 4096)
        }
        return 2560
    }
}
