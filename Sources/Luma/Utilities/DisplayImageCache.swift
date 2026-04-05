import AppKit
import Foundation

@MainActor
final class DisplayImageCache {
    static let shared = DisplayImageCache()

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
        memoryImage(forKey: asset.id.uuidString)
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
            let image = await self.loadImage(for: asset)
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

    private func loadImage(for asset: MediaAsset) async -> NSImage? {
        guard let sourceURL = asset.previewURL ?? asset.rawURL else {
            return nil
        }

        let maxPixelSize = recommendedMaxPixelSize(for: asset)
        guard let cgImage = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: maxPixelSize) else {
            return nil
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    private func recommendedMaxPixelSize(for asset: MediaAsset) -> Int {
        let sourceMax = max(asset.metadata.imageWidth, asset.metadata.imageHeight)
        if sourceMax > 0 {
            return min(sourceMax, 2400)
        }
        return 2200
    }
}
