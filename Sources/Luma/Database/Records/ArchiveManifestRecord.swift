import Foundation
import GRDB

struct ArchiveManifestRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "archive_manifests"

    var id: String
    var expeditionId: String?
    var albumId: String?
    var generatedAt: Double
    var archiveKind: String
    var itemsJSON: String
}
