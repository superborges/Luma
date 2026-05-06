import Foundation
import GRDB

final class AlbumManager: Sendable {
    private let db: LumaDatabase
    private let albumRepo: any AlbumRepository

    init(db: LumaDatabase, albumRepo: any AlbumRepository) {
        self.db = db
        self.albumRepo = albumRepo
    }

    // MARK: - Create

    func createManualAlbum(name: String, expeditionId: UUID? = nil) throws -> LumaAlbum {
        let now = Date()
        let record = AlbumRecord(
            id: UUID().uuidString,
            expeditionId: expeditionId?.uuidString,
            name: name,
            kind: AlbumKind.manual.rawValue,
            ruleJSON: nil,
            createdAt: now.timeIntervalSinceReferenceDate,
            updatedAt: now.timeIntervalSinceReferenceDate
        )
        try albumRepo.insert(record)
        guard let album = LumaAlbum(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct album from record")
        }
        return album
    }

    func createSmartAlbum(name: String, expeditionId: UUID? = nil, rule: SmartAlbumRule) throws -> LumaAlbum {
        let now = Date()
        let ruleJSON = try String(data: JSONEncoder().encode(rule), encoding: .utf8)
        let record = AlbumRecord(
            id: UUID().uuidString,
            expeditionId: expeditionId?.uuidString,
            name: name,
            kind: AlbumKind.smart.rawValue,
            ruleJSON: ruleJSON,
            createdAt: now.timeIntervalSinceReferenceDate,
            updatedAt: now.timeIntervalSinceReferenceDate
        )
        try albumRepo.insert(record)
        guard let album = LumaAlbum(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct smart album from record")
        }
        return album
    }

    // MARK: - Delete

    func deleteAlbum(id: UUID) throws {
        try albumRepo.deleteRef(albumId: id.uuidString)
        try albumRepo.delete(id: id.uuidString)
    }

    // MARK: - Fetch

    func fetchAlbum(id: UUID) throws -> LumaAlbum? {
        guard let record = try albumRepo.fetchOne(id: id.uuidString) else { return nil }
        return LumaAlbum(record: record)
    }

    func fetchAllAlbums() throws -> [LumaAlbum] {
        try albumRepo.fetchAll().compactMap { LumaAlbum(record: $0) }
    }

    func fetchAlbumsForExpedition(_ expeditionId: UUID) throws -> [LumaAlbum] {
        try albumRepo.fetchByExpedition(expeditionId.uuidString).compactMap { LumaAlbum(record: $0) }
    }

    func fetchAlbumAssetIds(albumId: UUID) throws -> [UUID] {
        try albumRepo.fetchAlbumAssets(albumId: albumId.uuidString).compactMap { UUID(uuidString: $0.assetId) }
    }

    func fetchAssetCount(albumId: UUID) throws -> Int {
        try albumRepo.fetchAssetCount(albumId: albumId.uuidString)
    }

    // MARK: - Asset Management

    func addAssets(albumId: UUID, assetIds: [UUID]) throws {
        let now = Date().timeIntervalSinceReferenceDate
        let existingCount = try albumRepo.fetchAssetCount(albumId: albumId.uuidString)
        let records = assetIds.enumerated().map { index, assetId in
            AlbumAssetRecord(
                albumId: albumId.uuidString,
                assetId: assetId.uuidString,
                addedAt: now,
                localOrder: existingCount + index
            )
        }
        try albumRepo.addAssetsBatch(records)
    }

    func removeAssets(albumId: UUID, assetIds: [UUID]) throws {
        try albumRepo.removeAssets(
            albumId: albumId.uuidString,
            assetIds: assetIds.map(\.uuidString)
        )
    }

    // MARK: - Smart Album Evaluation

    func evaluateSmartRule(_ rule: SmartAlbumRule, expeditionId: UUID? = nil) throws -> [UUID] {
        let scopeExpeditionId: String? = {
            switch rule.scope {
            case .library: return nil
            case .expedition(let id): return id.uuidString
            }
        }()

        let effectiveExpeditionId = scopeExpeditionId ?? expeditionId?.uuidString

        guard let filter = rule.filters.first else { return [] }

        return try db.dbQueue.read { db in
            try self.evaluateFilter(filter, expeditionId: effectiveExpeditionId, db: db)
        }
    }

    private func evaluateFilter(_ filter: SmartAlbumFilter, expeditionId: String?, db: Database) throws -> [UUID] {
        switch filter {
        case .allPicked:
            return try fetchAssetIdsByDecision("picked", expeditionId: expeditionId, db: db)
        case .allRejected:
            return try fetchAssetIdsByDecision("rejected", expeditionId: expeditionId, db: db)
        case .unreviewed:
            return try fetchAssetIdsByDecision("pending", expeditionId: expeditionId, db: db)
        case .archived:
            return try fetchArchivedAssetIds(expeditionId: expeditionId, db: db)
        case .highScore:
            return try fetchHighScoreAssetIds(threshold: 80, db: db)
        case .cleanupCandidates:
            return try fetchCleanupCandidateIds(expeditionId: expeditionId, db: db)
        }
    }

    private func fetchAssetIdsByDecision(_ decision: String, expeditionId: String?, db: Database) throws -> [UUID] {
        var query = ExpeditionAssetRecord
            .filter(Column("decision") == decision)
        if let eid = expeditionId {
            query = query.filter(Column("expeditionId") == eid)
        }
        let records = try query.fetchAll(db)
        return records.compactMap { UUID(uuidString: $0.assetId) }
    }

    private func fetchArchivedAssetIds(expeditionId: String?, db: Database) throws -> [UUID] {
        var query = ExpeditionAssetRecord
            .filter(Column("isArchived") == true)
        if let eid = expeditionId {
            query = query.filter(Column("expeditionId") == eid)
        }
        let records = try query.fetchAll(db)
        return records.compactMap { UUID(uuidString: $0.assetId) }
    }

    private func fetchHighScoreAssetIds(threshold: Int, db: Database) throws -> [UUID] {
        let sql = """
            SELECT DISTINCT s.assetId FROM asset_scores s
            INNER JOIN (
                SELECT assetId, MAX(timestamp) as maxTs FROM asset_scores GROUP BY assetId
            ) latest ON s.assetId = latest.assetId AND s.timestamp = latest.maxTs
            WHERE s.overall >= ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [threshold])
        return rows.compactMap { UUID(uuidString: $0["assetId"]) }
    }

    private func fetchCleanupCandidateIds(expeditionId: String?, db: Database) throws -> [UUID] {
        var candidates = Set(try fetchAssetIdsByDecision("rejected", expeditionId: expeditionId, db: db))
        let lowScoreRows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT s.assetId FROM asset_scores s
            INNER JOIN (
                SELECT assetId, MAX(timestamp) as maxTs FROM asset_scores GROUP BY assetId
            ) latest ON s.assetId = latest.assetId AND s.timestamp = latest.maxTs
            WHERE s.overall < 40
            """)
        let lowScoreIds = lowScoreRows.compactMap { UUID(uuidString: $0["assetId"]) }
        candidates.formUnion(lowScoreIds)
        return Array(candidates)
    }

    // MARK: - External Album Ref

    func fetchExternalRef(albumId: UUID) throws -> ExternalAlbumRef? {
        guard let record = try albumRepo.fetchRef(albumId: albumId.uuidString) else { return nil }
        return ExternalAlbumRef(record: record)
    }

    func saveExternalRef(_ ref: ExternalAlbumRef) throws {
        try albumRepo.insertRef(ref.toRecord())
    }

    func deleteExternalRef(albumId: UUID) throws {
        try albumRepo.deleteRef(albumId: albumId.uuidString)
    }

    // MARK: - Album Sync Lifecycle

    func markAlbumAsSynced(albumId: UUID, ref: ExternalAlbumRef) throws {
        try albumRepo.deleteRef(albumId: albumId.uuidString)
        try albumRepo.insertRef(ref.toRecord())
        guard var record = try albumRepo.fetchOne(id: albumId.uuidString) else { return }
        record.kind = AlbumKind.photosBacked.rawValue
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try albumRepo.update(record)
    }

    func convertToLocalAlbum(albumId: UUID) throws {
        try albumRepo.deleteRef(albumId: albumId.uuidString)
        guard var record = try albumRepo.fetchOne(id: albumId.uuidString) else { return }
        record.kind = AlbumKind.manual.rawValue
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try albumRepo.update(record)
    }

    func validateAlbumRef(albumId: UUID, adapter: any AlbumSyncAdapter) async throws -> Bool {
        guard let ref = try fetchExternalRef(albumId: albumId) else { return false }
        return try await adapter.validateAccess(ref)
    }
}
