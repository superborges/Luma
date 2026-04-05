import Foundation

struct ThumbnailCacheSnapshot: Hashable {
    let memoryHits: Int
    let diskHits: Int
    let inflightJoins: Int
    let generatedImages: Int
    let preheatedItems: Int
    let trimEvictions: Int
    let activeMemoryItems: Int
    let inflightLoads: Int

    static let empty = ThumbnailCacheSnapshot(
        memoryHits: 0,
        diskHits: 0,
        inflightJoins: 0,
        generatedImages: 0,
        preheatedItems: 0,
        trimEvictions: 0,
        activeMemoryItems: 0,
        inflightLoads: 0
    )
}

struct DisplayImageCacheSnapshot: Hashable {
    let memoryHits: Int
    let inflightJoins: Int
    let decodedImages: Int
    let preheatedItems: Int
    let trimEvictions: Int
    let activeMemoryItems: Int
    let inflightLoads: Int

    static let empty = DisplayImageCacheSnapshot(
        memoryHits: 0,
        inflightJoins: 0,
        decodedImages: 0,
        preheatedItems: 0,
        trimEvictions: 0,
        activeMemoryItems: 0,
        inflightLoads: 0
    )
}
