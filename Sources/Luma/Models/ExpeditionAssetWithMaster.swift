import Foundation

struct ExpeditionAssetWithMaster: Identifiable, Sendable {
    let expeditionAsset: ExpeditionAsset
    let masterAsset: MasterAsset
    var latestScore: AssetScoreRecord?

    var id: UUID { expeditionAsset.id }
    var assetId: UUID { masterAsset.id }
    var baseName: String { masterAsset.baseName }
    var decision: Decision { expeditionAsset.decision }
    var rating: Int? { expeditionAsset.rating }
    var isRecommended: Bool { expeditionAsset.isRecommended }
    var isBestInGroup: Bool { expeditionAsset.isBestInGroup }
    var mediaType: MediaType { masterAsset.mediaType }

    var existingImageFileURL: URL? { masterAsset.existingImageFileURL }

    var isReferenceInvalid: Bool {
        guard masterAsset.storageMode == .referenced else { return false }
        guard let url = masterAsset.originalURL ?? masterAsset.previewURL ?? masterAsset.rawURL else { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    var effectiveRating: Int {
        if let rating = expeditionAsset.rating {
            return min(max(rating, 1), 5)
        }
        guard let overall = latestScore?.overall else { return 1 }
        switch overall {
        case 90...: return 5
        case 75..<90: return 4
        case 60..<75: return 3
        case 45..<60: return 2
        default: return 1
        }
    }
}

struct PhotoGroupWithAssets: Identifiable, Sendable {
    let id: UUID
    var name: String
    var coverAssetId: UUID?
    var groupComment: String?
    var timeRange: ClosedRange<Date>?
    var location: Coordinate?
    var reviewed: Bool
    var assets: [ExpeditionAssetWithMaster]
    var recommendedAssetIds: [UUID]

    var assetCount: Int { assets.count }

    var pickedCount: Int {
        assets.count(where: { $0.decision == .picked })
    }

    var rejectedCount: Int {
        assets.count(where: { $0.decision == .rejected })
    }

    var pendingCount: Int {
        assets.count(where: { $0.decision == .pending })
    }

    init?(record: PhotoGroupRecord, assets: [ExpeditionAssetWithMaster], recommendedAssetIds: [UUID]) {
        guard let uuid = UUID(uuidString: record.id) else { return nil }
        self.id = uuid
        self.name = record.name ?? "未命名分组"
        self.coverAssetId = record.coverAssetId.flatMap { UUID(uuidString: $0) }
        self.groupComment = record.groupComment
        if let start = record.timeRangeStart, let end = record.timeRangeEnd {
            let s = Date(timeIntervalSinceReferenceDate: start)
            let e = Date(timeIntervalSinceReferenceDate: end)
            self.timeRange = s <= e ? s...e : e...s
        } else {
            self.timeRange = nil
        }
        if let lat = record.latitude, let lon = record.longitude {
            self.location = Coordinate(latitude: lat, longitude: lon)
        } else {
            self.location = nil
        }
        self.reviewed = record.reviewed
        self.assets = assets
        self.recommendedAssetIds = recommendedAssetIds
    }
}
