import Foundation
import GRDB

struct ExpeditionRecommendationRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "expedition_recommendations"

    var id: String
    var expeditionId: String
    var assetId: String
    var groupId: String?
    var recommendationType: String
    var score: Int?
    var reason: String?
    var createdAt: Double
}
