import Foundation
import GRDB

struct AlbumRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "albums"

    var id: String
    var expeditionId: String?
    var name: String
    var kind: String
    var ruleJSON: String?
    var createdAt: Double
    var updatedAt: Double
}

struct AlbumAssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "album_assets"

    var albumId: String
    var assetId: String
    var addedAt: Double
    var localOrder: Int
}

struct ExternalAlbumRefRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "external_album_refs"

    var albumId: String
    var provider: String
    var localIdentifier: String
}
