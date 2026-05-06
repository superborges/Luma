import Foundation
import GRDB

struct ImportSessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "import_sessions"

    var id: String
    var sourceId: String?
    var targetExpeditionId: String?
    var startedAt: Double
    var completedAt: Double?
    var status: String
    var totalItems: Int
    var importedCount: Int
    var skippedCount: Int
    var failedItems: String?
}
