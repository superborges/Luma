import Foundation
import GRDB

struct AssetScoreRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "asset_scores"

    var id: String
    var assetId: String
    var provider: String
    var composition: Int?
    var exposure: Int?
    var color: Int?
    var sharpness: Int?
    var story: Int?
    var overall: Int?
    var comment: String?
    var recommended: Bool?
    var timestamp: Double
}
