import Foundation
import GRDB

protocol ImportSessionRepository: Sendable {
    func insert(_ record: ImportSessionRecord) throws
    func update(_ record: ImportSessionRecord) throws
    func fetchByExpedition(_ expeditionId: String) throws -> [ImportSessionRecord]
    func fetchPending() throws -> [ImportSessionRecord]
}

final class GRDBImportSessionRepository: ImportSessionRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: ImportSessionRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: ImportSessionRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [ImportSessionRecord] {
        try dbQueue.read { db in
            try ImportSessionRecord
                .filter(Column("targetExpeditionId") == expeditionId)
                .fetchAll(db)
        }
    }

    func fetchPending() throws -> [ImportSessionRecord] {
        try dbQueue.read { db in
            try ImportSessionRecord
                .filter(Column("status") == "pending")
                .fetchAll(db)
        }
    }
}
