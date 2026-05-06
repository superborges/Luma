import Foundation
import GRDB

struct PhotoGroupRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "photo_groups"

    var id: String
    var expeditionId: String
    var name: String?
    var coverAssetId: String?
    var groupComment: String?
    var timeRangeStart: Double?
    var timeRangeEnd: Double?
    var latitude: Double?
    var longitude: Double?
    var reviewed: Bool
    var createdAt: Double
    var updatedAt: Double
}

struct PhotoGroupAssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "photo_group_assets"

    var groupId: String
    var assetId: String
    var isRecommended: Bool
}

struct PhotoSubGroupRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "photo_subgroups"

    var id: String
    var groupId: String
    var bestAssetId: String?
    var recommendedAssetId: String?
    var reasonSummary: String?
    var reviewed: Bool
}

struct PhotoSubGroupAssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "photo_subgroup_assets"

    var subgroupId: String
    var assetId: String
}
