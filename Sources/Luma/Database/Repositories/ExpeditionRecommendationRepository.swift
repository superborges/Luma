import Foundation
import GRDB

protocol ExpeditionRecommendationRepository: Sendable {
    func insert(_ record: ExpeditionRecommendationRecord) throws
    func update(_ record: ExpeditionRecommendationRecord) throws
    func delete(id: String) throws
    func fetchByExpedition(_ expeditionId: String) throws -> [ExpeditionRecommendationRecord]
    func fetchByAsset(_ assetId: String) throws -> [ExpeditionRecommendationRecord]
}

final class GRDBExpeditionRecommendationRepository: ExpeditionRecommendationRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: ExpeditionRecommendationRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: ExpeditionRecommendationRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try ExpeditionRecommendationRecord.deleteOne(db, key: id)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [ExpeditionRecommendationRecord] {
        try dbQueue.read { db in
            try ExpeditionRecommendationRecord
                .filter(Column("expeditionId") == expeditionId)
                .fetchAll(db)
        }
    }

    func fetchByAsset(_ assetId: String) throws -> [ExpeditionRecommendationRecord] {
        try dbQueue.read { db in
            try ExpeditionRecommendationRecord
                .filter(Column("assetId") == assetId)
                .fetchAll(db)
        }
    }
}
