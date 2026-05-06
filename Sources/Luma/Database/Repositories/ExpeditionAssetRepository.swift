import Foundation
import GRDB

protocol ExpeditionAssetRepository: Sendable {
    func insert(_ record: ExpeditionAssetRecord) throws
    func insertBatch(_ records: [ExpeditionAssetRecord]) throws
    func update(_ record: ExpeditionAssetRecord) throws
    func delete(id: String) throws
    func fetchByExpedition(_ expeditionId: String) throws -> [ExpeditionAssetRecord]
    func fetchByAsset(_ assetId: String) throws -> [ExpeditionAssetRecord]
    func fetchByExpeditionAndDecision(_ expeditionId: String, decision: String) throws -> [ExpeditionAssetRecord]
    func setDecision(id: String, decision: String) throws
    func exists(expeditionId: String, assetId: String) throws -> Bool
    func fetchCountByExpedition(_ expeditionId: String) throws -> Int
}

final class GRDBExpeditionAssetRepository: ExpeditionAssetRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: ExpeditionAssetRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func insertBatch(_ records: [ExpeditionAssetRecord]) throws {
        guard !records.isEmpty else { return }
        try dbQueue.write { db in
            for record in records {
                try record.insert(db)
            }
        }
    }

    func update(_ record: ExpeditionAssetRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try ExpeditionAssetRecord.deleteOne(db, key: id)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [ExpeditionAssetRecord] {
        try dbQueue.read { db in
            try ExpeditionAssetRecord.filter(Column("expeditionId") == expeditionId).fetchAll(db)
        }
    }

    func fetchByAsset(_ assetId: String) throws -> [ExpeditionAssetRecord] {
        try dbQueue.read { db in
            try ExpeditionAssetRecord.filter(Column("assetId") == assetId).fetchAll(db)
        }
    }

    func fetchByExpeditionAndDecision(_ expeditionId: String, decision: String) throws -> [ExpeditionAssetRecord] {
        try dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expeditionId && Column("decision") == decision)
                .fetchAll(db)
        }
    }

    func setDecision(id: String, decision: String) throws {
        try dbQueue.write { db in
            guard var record = try ExpeditionAssetRecord.fetchOne(db, key: id) else { return }
            record.decision = decision
            record.updatedAt = Date().timeIntervalSinceReferenceDate
            try record.update(db)
        }
    }

    func exists(expeditionId: String, assetId: String) throws -> Bool {
        try dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expeditionId && Column("assetId") == assetId)
                .fetchCount(db) > 0
        }
    }

    func fetchCountByExpedition(_ expeditionId: String) throws -> Int {
        try dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expeditionId)
                .fetchCount(db)
        }
    }
}
