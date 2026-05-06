import Foundation
import GRDB

struct ExpeditionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "expeditions"

    var id: String
    var name: String
    var subtitle: String?
    var description: String?
    var coverAssetId: String?
    var startDate: Double?
    var endDate: Double?
    var sourceMode: String
    var status: String
    var isMacPhotos: Bool
    var createdAt: Double
    var updatedAt: Double
}
