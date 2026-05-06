import Foundation
import GRDB

protocol AssetScoreRepository: Sendable {
    func insert(_ record: AssetScoreRecord) throws
    func update(_ record: AssetScoreRecord) throws
    func fetchByAsset(_ assetId: String) throws -> [AssetScoreRecord]
    func fetchLatestByAsset(_ assetId: String) throws -> AssetScoreRecord?
    func fetchLatestByAssets(_ assetIds: [String]) throws -> [String: AssetScoreRecord]
}

final class GRDBAssetScoreRepository: AssetScoreRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: AssetScoreRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: AssetScoreRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func fetchByAsset(_ assetId: String) throws -> [AssetScoreRecord] {
        try dbQueue.read { db in
            try AssetScoreRecord.filter(Column("assetId") == assetId).fetchAll(db)
        }
    }

    func fetchLatestByAsset(_ assetId: String) throws -> AssetScoreRecord? {
        try dbQueue.read { db in
            try AssetScoreRecord
                .filter(Column("assetId") == assetId)
                .order(Column("timestamp").desc)
                .fetchOne(db)
        }
    }

    func fetchLatestByAssets(_ assetIds: [String]) throws -> [String: AssetScoreRecord] {
        guard !assetIds.isEmpty else { return [:] }
        let chunkSize = 500
        var result: [String: AssetScoreRecord] = [:]
        for chunk in stride(from: 0, to: assetIds.count, by: chunkSize).map({ Array(assetIds[$0..<min($0 + chunkSize, assetIds.count)]) }) {
            try dbQueue.read { db in
                let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                let sql = """
                    SELECT s.* FROM asset_scores s
                    INNER JOIN (
                        SELECT assetId, MAX(timestamp) AS maxTs
                        FROM asset_scores
                        WHERE assetId IN (\(placeholders))
                        GROUP BY assetId
                    ) latest ON s.assetId = latest.assetId AND s.timestamp = latest.maxTs
                    ORDER BY s.rowid DESC
                    """
                let records = try AssetScoreRecord.fetchAll(
                    db, sql: sql, arguments: StatementArguments(chunk)
                )
                for r in records {
                    if result[r.assetId] == nil { result[r.assetId] = r }
                }
            }
        }
        return result
    }
}
