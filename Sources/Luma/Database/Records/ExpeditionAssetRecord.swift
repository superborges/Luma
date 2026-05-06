import Foundation
import GRDB

struct ExpeditionAssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "expedition_assets"

    var id: String
    var expeditionId: String
    var assetId: String
    var addedAt: Double
    var addedBy: String
    var localOrder: Int
    var decision: String
    var rating: Int?
    var colorLabel: String?
    var isRecommended: Bool
    var isBestInGroup: Bool
    var isUserOverride: Bool
    var isArchived: Bool
    var isHiddenInExpedition: Bool
    var updatedAt: Double
}
