import Foundation
import GRDB

protocol ExpeditionRepository: Sendable {
    func insert(_ record: ExpeditionRecord) throws
    func update(_ record: ExpeditionRecord) throws
    func delete(id: String) throws
    func fetchById(_ id: String) throws -> ExpeditionRecord?
    func fetchAll() throws -> [ExpeditionRecord]
    func fetchNonMacPhotos() throws -> [ExpeditionRecord]
    func fetchMacPhotos() throws -> [ExpeditionRecord]
}

final class GRDBExpeditionRepository: ExpeditionRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: ExpeditionRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: ExpeditionRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try ExpeditionRecord.deleteOne(db, key: id)
        }
    }

    func fetchById(_ id: String) throws -> ExpeditionRecord? {
        try dbQueue.read { db in
            try ExpeditionRecord.fetchOne(db, key: id)
        }
    }

    func fetchAll() throws -> [ExpeditionRecord] {
        try dbQueue.read { db in
            try ExpeditionRecord.fetchAll(db)
        }
    }

    func fetchNonMacPhotos() throws -> [ExpeditionRecord] {
        try dbQueue.read { db in
            try ExpeditionRecord.filter(Column("isMacPhotos") == false).fetchAll(db)
        }
    }

    func fetchMacPhotos() throws -> [ExpeditionRecord] {
        try dbQueue.read { db in
            try ExpeditionRecord.filter(Column("isMacPhotos") == true).fetchAll(db)
        }
    }
}
