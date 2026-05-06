import Foundation
import GRDB

struct AssetSourceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "asset_sources"

    var id: String
    var kind: String
    var displayName: String
    var rootIdentifier: String?
    var isMutable: Bool
    var supportsDelete: Bool
    var supportsAlbumWrite: Bool
    var supportsOriginalAccess: Bool
    var createdAt: Double
    var updatedAt: Double
}
