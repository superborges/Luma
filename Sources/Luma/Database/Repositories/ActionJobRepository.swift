import Foundation
import GRDB

protocol ActionJobRepository: Sendable {
    func insert(_ record: ActionJobRecord) throws
    func update(_ record: ActionJobRecord) throws
    func fetchOne(id: String) throws -> ActionJobRecord?
    func fetchAll() throws -> [ActionJobRecord]
    func fetchByExpedition(_ expeditionId: String) throws -> [ActionJobRecord]
    func fetchByStatus(_ status: String) throws -> [ActionJobRecord]
    func fetchByExpeditionAndStatus(expeditionId: String, status: String) throws -> [ActionJobRecord]
    func fetchPending() throws -> [ActionJobRecord]
    func fetchCompleted() throws -> [ActionJobRecord]
    func fetchActive() throws -> [ActionJobRecord]
}

final class GRDBActionJobRepository: ActionJobRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: ActionJobRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: ActionJobRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [ActionJobRecord] {
        try dbQueue.read { db in
            try ActionJobRecord
                .filter(Column("expeditionId") == expeditionId)
                .fetchAll(db)
        }
    }

    func fetchOne(id: String) throws -> ActionJobRecord? {
        try dbQueue.read { db in
            try ActionJobRecord.fetchOne(db, key: id)
        }
    }

    func fetchAll() throws -> [ActionJobRecord] {
        try dbQueue.read { db in
            try ActionJobRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchByStatus(_ status: String) throws -> [ActionJobRecord] {
        try dbQueue.read { db in
            try ActionJobRecord
                .filter(Column("status") == status || (status == "pending" && Column("status") == "queued"))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchByExpeditionAndStatus(expeditionId: String, status: String) throws -> [ActionJobRecord] {
        try dbQueue.read { db in
            try ActionJobRecord
                .filter(Column("expeditionId") == expeditionId)
                .filter(Column("status") == status || (status == "pending" && Column("status") == "queued"))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchPending() throws -> [ActionJobRecord] {
        try fetchByStatus("pending")
    }

    func fetchCompleted() throws -> [ActionJobRecord] {
        try fetchByStatus("completed")
    }

    func fetchActive() throws -> [ActionJobRecord] {
        try dbQueue.read { db in
            try ActionJobRecord
                .filter([
                    "pending", "queued", "running"
                ].contains(Column("status")))
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }
}
