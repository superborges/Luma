import Foundation
import GRDB

protocol MasterAssetRepository: Sendable {
    func insert(_ record: MasterAssetRecord) throws
    func update(_ record: MasterAssetRecord) throws
    func delete(id: String) throws
    func fetchById(_ id: String) throws -> MasterAssetRecord?
    func fetchByContentHash(_ hash: String) throws -> MasterAssetRecord?
    func fetchByExternalId(_ externalId: String) throws -> MasterAssetRecord?
    func fetchAll() throws -> [MasterAssetRecord]
    func fetchCount() throws -> Int
    func fetchRecentlyAdded(limit: Int) throws -> [MasterAssetRecord]
    func fetchUnorganized(limit: Int) throws -> [MasterAssetRecord]
    func fetchBySourceKind(_ kind: String, orderedBy: Column, ascending: Bool) throws -> [MasterAssetRecord]
    func fetchBySourceKindAndDateRange(_ kind: String, from: Double, to: Double) throws -> [MasterAssetRecord]
    func fetchByExternalIds(_ externalIds: [String]) throws -> [MasterAssetRecord]
    func fetchByIds(_ ids: [String]) throws -> [MasterAssetRecord]
}

final class GRDBMasterAssetRepository: MasterAssetRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: MasterAssetRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: MasterAssetRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try MasterAssetRecord.deleteOne(db, key: id)
        }
    }

    func fetchById(_ id: String) throws -> MasterAssetRecord? {
        try dbQueue.read { db in
            try MasterAssetRecord.fetchOne(db, key: id)
        }
    }

    func fetchByContentHash(_ hash: String) throws -> MasterAssetRecord? {
        try dbQueue.read { db in
            try MasterAssetRecord.filter(Column("contentHash") == hash).fetchOne(db)
        }
    }

    func fetchByExternalId(_ externalId: String) throws -> MasterAssetRecord? {
        try dbQueue.read { db in
            try MasterAssetRecord.filter(Column("externalIdentifier") == externalId).fetchOne(db)
        }
    }

    func fetchAll() throws -> [MasterAssetRecord] {
        try dbQueue.read { db in
            try MasterAssetRecord.fetchAll(db)
        }
    }

    func fetchCount() throws -> Int {
        try dbQueue.read { db in
            try MasterAssetRecord.fetchCount(db)
        }
    }

    func fetchRecentlyAdded(limit: Int) throws -> [MasterAssetRecord] {
        try dbQueue.read { db in
            try MasterAssetRecord
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchUnorganized(limit: Int) throws -> [MasterAssetRecord] {
        try dbQueue.read { db in
            let sql = """
                SELECT m.* FROM master_assets m
                LEFT JOIN expedition_assets ea ON ea.assetId = m.id
                WHERE ea.id IS NULL
                ORDER BY m.createdAt DESC
                LIMIT ?
                """
            return try MasterAssetRecord.fetchAll(db, sql: sql, arguments: [limit])
        }
    }

    func fetchBySourceKind(_ kind: String, orderedBy column: Column, ascending: Bool) throws -> [MasterAssetRecord] {
        try dbQueue.read { db in
            try MasterAssetRecord
                .filter(Column("sourceKind") == kind)
                .order(ascending ? column.asc : column.desc)
                .fetchAll(db)
        }
    }

    func fetchBySourceKindAndDateRange(_ kind: String, from: Double, to: Double) throws -> [MasterAssetRecord] {
        try dbQueue.read { db in
            try MasterAssetRecord
                .filter(Column("sourceKind") == kind)
                .filter(Column("captureDate") >= from && Column("captureDate") <= to)
                .order(Column("captureDate").desc)
                .fetchAll(db)
        }
    }

    func fetchByExternalIds(_ externalIds: [String]) throws -> [MasterAssetRecord] {
        guard !externalIds.isEmpty else { return [] }
        let chunkSize = 500
        return try dbQueue.read { db in
            var results: [MasterAssetRecord] = []
            for offset in stride(from: 0, to: externalIds.count, by: chunkSize) {
                let chunk = Array(externalIds[offset..<min(offset + chunkSize, externalIds.count)])
                let records = try MasterAssetRecord
                    .filter(chunk.contains(Column("externalIdentifier")))
                    .fetchAll(db)
                results.append(contentsOf: records)
            }
            return results
        }
    }

    func fetchByIds(_ ids: [String]) throws -> [MasterAssetRecord] {
        guard !ids.isEmpty else { return [] }
        let chunkSize = 500
        return try dbQueue.read { db in
            var results: [MasterAssetRecord] = []
            for offset in stride(from: 0, to: ids.count, by: chunkSize) {
                let chunk = Array(ids[offset..<min(offset + chunkSize, ids.count)])
                let records = try MasterAssetRecord
                    .filter(keys: chunk)
                    .fetchAll(db)
                results.append(contentsOf: records)
            }
            return results
        }
    }
}
