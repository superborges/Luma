import Foundation
import GRDB

final class LumaDatabase: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        var migrator = DatabaseMigrator()
        Self.registerMigrations(&migrator)
        try migrator.migrate(dbQueue)
    }

    convenience init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: path, configuration: config)
        try self.init(dbQueue: queue)
    }

    /// In-memory database for testing
    static func inMemory() throws -> LumaDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(configuration: config)
        return try LumaDatabase(dbQueue: queue)
    }

    /// Default on-disk database at ~/Library/Application Support/Luma/library.db
    static func `default`() throws -> LumaDatabase {
        let root = try AppDirectories.applicationSupportRoot()
        let dbPath = root.appendingPathComponent("library.db").path
        return try LumaDatabase(path: dbPath)
    }

    // MARK: - Migrations

    private static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            // asset_sources
            try db.create(table: "asset_sources") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("rootIdentifier", .text)
                t.column("isMutable", .boolean).notNull().defaults(to: false)
                t.column("supportsDelete", .boolean).notNull().defaults(to: false)
                t.column("supportsAlbumWrite", .boolean).notNull().defaults(to: false)
                t.column("supportsOriginalAccess", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // master_assets
            try db.create(table: "master_assets") { t in
                t.primaryKey("id", .text)
                t.column("sourceId", .text).references("asset_sources", onDelete: .setNull)
                t.column("sourceKind", .text).notNull()
                t.column("storageMode", .text).notNull()
                t.column("externalIdentifier", .text)
                t.column("originalURL", .text)
                t.column("localManagedURL", .text)
                t.column("previewURL", .text)
                t.column("rawURL", .text)
                t.column("livePhotoVideoURL", .text)
                t.column("thumbnailCacheURL", .text)
                t.column("previewCacheURL", .text)
                t.column("fingerprint", .text)
                t.column("contentHash", .text)
                t.column("baseName", .text).notNull()
                t.column("mediaType", .text).notNull()
                t.column("captureDate", .double)
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("focalLength", .double)
                t.column("aperture", .double)
                t.column("shutterSpeed", .text)
                t.column("iso", .integer)
                t.column("cameraModel", .text)
                t.column("lensModel", .text)
                t.column("imageWidth", .integer)
                t.column("imageHeight", .integer)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(index: "idx_master_assets_sourceId", on: "master_assets", columns: ["sourceId"])
            try db.create(index: "idx_master_assets_contentHash", on: "master_assets", columns: ["contentHash"])
            try db.create(index: "idx_master_assets_externalIdentifier", on: "master_assets", columns: ["externalIdentifier"])

            // expeditions
            try db.create(table: "expeditions") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("subtitle", .text)
                t.column("description", .text)
                t.column("coverAssetId", .text)
                t.column("startDate", .double)
                t.column("endDate", .double)
                t.column("sourceMode", .text).notNull()
                t.column("status", .text).notNull()
                t.column("isMacPhotos", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // expedition_assets
            try db.create(table: "expedition_assets") { t in
                t.primaryKey("id", .text)
                t.column("expeditionId", .text).notNull().references("expeditions", onDelete: .cascade)
                t.column("assetId", .text).notNull().references("master_assets", onDelete: .cascade)
                t.column("addedAt", .double).notNull()
                t.column("addedBy", .text).notNull()
                t.column("localOrder", .integer).notNull().defaults(to: 0)
                t.column("decision", .text).notNull().defaults(to: "pending")
                t.column("rating", .integer)
                t.column("colorLabel", .text)
                t.column("isRecommended", .boolean).notNull().defaults(to: false)
                t.column("isBestInGroup", .boolean).notNull().defaults(to: false)
                t.column("isUserOverride", .boolean).notNull().defaults(to: false)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("isHiddenInExpedition", .boolean).notNull().defaults(to: false)
                t.column("updatedAt", .double).notNull()
                t.uniqueKey(["expeditionId", "assetId"])
            }
            try db.create(index: "idx_expedition_assets_expeditionId", on: "expedition_assets", columns: ["expeditionId"])
            try db.create(index: "idx_expedition_assets_assetId", on: "expedition_assets", columns: ["assetId"])
            try db.create(index: "idx_expedition_assets_decision", on: "expedition_assets", columns: ["decision"])

            // photo_groups
            try db.create(table: "photo_groups") { t in
                t.primaryKey("id", .text)
                t.column("expeditionId", .text).notNull().references("expeditions", onDelete: .cascade)
                t.column("name", .text)
                t.column("coverAssetId", .text)
                t.column("groupComment", .text)
                t.column("timeRangeStart", .double)
                t.column("timeRangeEnd", .double)
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("reviewed", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(index: "idx_photo_groups_expeditionId", on: "photo_groups", columns: ["expeditionId"])

            // photo_group_assets
            try db.create(table: "photo_group_assets") { t in
                t.column("groupId", .text).notNull().references("photo_groups", onDelete: .cascade)
                t.column("assetId", .text).notNull().references("master_assets", onDelete: .cascade)
                t.column("isRecommended", .boolean).notNull().defaults(to: false)
                t.primaryKey(["groupId", "assetId"])
            }

            // photo_subgroups
            try db.create(table: "photo_subgroups") { t in
                t.primaryKey("id", .text)
                t.column("groupId", .text).notNull().references("photo_groups", onDelete: .cascade)
                t.column("bestAssetId", .text)
                t.column("recommendedAssetId", .text)
                t.column("reasonSummary", .text)
                t.column("reviewed", .boolean).notNull().defaults(to: false)
            }

            // photo_subgroup_assets
            try db.create(table: "photo_subgroup_assets") { t in
                t.column("subgroupId", .text).notNull().references("photo_subgroups", onDelete: .cascade)
                t.column("assetId", .text).notNull().references("master_assets", onDelete: .cascade)
                t.primaryKey(["subgroupId", "assetId"])
            }

            // asset_scores
            try db.create(table: "asset_scores") { t in
                t.primaryKey("id", .text)
                t.column("assetId", .text).notNull().references("master_assets", onDelete: .cascade)
                t.column("provider", .text).notNull()
                t.column("composition", .integer)
                t.column("exposure", .integer)
                t.column("color", .integer)
                t.column("sharpness", .integer)
                t.column("story", .integer)
                t.column("overall", .integer)
                t.column("comment", .text)
                t.column("recommended", .boolean)
                t.column("timestamp", .double).notNull()
            }
            try db.create(index: "idx_asset_scores_assetId", on: "asset_scores", columns: ["assetId"])

            // import_sessions
            try db.create(table: "import_sessions") { t in
                t.primaryKey("id", .text)
                t.column("sourceId", .text).references("asset_sources", onDelete: .setNull)
                t.column("targetExpeditionId", .text).references("expeditions", onDelete: .setNull)
                t.column("startedAt", .double).notNull()
                t.column("completedAt", .double)
                t.column("status", .text).notNull()
                t.column("totalItems", .integer).notNull().defaults(to: 0)
                t.column("importedCount", .integer).notNull().defaults(to: 0)
                t.column("skippedCount", .integer).notNull().defaults(to: 0)
                t.column("failedItems", .text)
            }
            try db.create(index: "idx_import_sessions_targetExpeditionId", on: "import_sessions", columns: ["targetExpeditionId"])

            // albums
            try db.create(table: "albums") { t in
                t.primaryKey("id", .text)
                t.column("expeditionId", .text).references("expeditions", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("ruleJSON", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(index: "idx_albums_expeditionId", on: "albums", columns: ["expeditionId"])

            // album_assets
            try db.create(table: "album_assets") { t in
                t.column("albumId", .text).notNull().references("albums", onDelete: .cascade)
                t.column("assetId", .text).notNull().references("master_assets", onDelete: .cascade)
                t.column("addedAt", .double).notNull()
                t.column("localOrder", .integer).notNull().defaults(to: 0)
                t.primaryKey(["albumId", "assetId"])
            }

            // external_album_refs
            try db.create(table: "external_album_refs") { t in
                t.primaryKey("albumId", .text).references("albums", onDelete: .cascade)
                t.column("provider", .text).notNull()
                t.column("localIdentifier", .text).notNull()
            }

            // expedition_recommendations
            try db.create(table: "expedition_recommendations") { t in
                t.primaryKey("id", .text)
                t.column("expeditionId", .text).notNull().references("expeditions", onDelete: .cascade)
                t.column("assetId", .text).notNull().references("master_assets", onDelete: .cascade)
                t.column("groupId", .text).references("photo_groups", onDelete: .cascade)
                t.column("recommendationType", .text).notNull()
                t.column("score", .integer)
                t.column("reason", .text)
                t.column("createdAt", .double).notNull()
            }
            try db.create(index: "idx_expedition_recommendations_expeditionId", on: "expedition_recommendations", columns: ["expeditionId"])
            try db.create(index: "idx_expedition_recommendations_assetId", on: "expedition_recommendations", columns: ["assetId"])

            // archive_manifests
            try db.create(table: "archive_manifests") { t in
                t.primaryKey("id", .text)
                t.column("expeditionId", .text).references("expeditions", onDelete: .cascade)
                t.column("albumId", .text).references("albums", onDelete: .cascade)
                t.column("generatedAt", .double).notNull()
                t.column("archiveKind", .text).notNull()
                t.column("itemsJSON", .text).notNull()
            }

            // action_jobs
            try db.create(table: "action_jobs") { t in
                t.primaryKey("id", .text)
                t.column("expeditionId", .text).references("expeditions", onDelete: .cascade)
                t.column("albumId", .text).references("albums", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("targetAssetIdsJSON", .text)
                t.column("status", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("completedAt", .double)
                t.column("resultURL", .text)
                t.column("errorMessage", .text)
            }
        }

        migrator.registerMigration("v2_mac_photos_indexes") { db in
            try db.create(
                index: "idx_master_assets_sourceKind_captureDate",
                on: "master_assets",
                columns: ["sourceKind", "captureDate"]
            )
        }
    }
}
