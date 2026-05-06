import Foundation
import GRDB

struct ActionJobRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "action_jobs"

    var id: String
    var expeditionId: String?
    var albumId: String?
    var kind: String
    var targetAssetIdsJSON: String?
    var status: String
    var createdAt: Double
    var completedAt: Double?
    var resultURL: String?
    var errorMessage: String?
}
