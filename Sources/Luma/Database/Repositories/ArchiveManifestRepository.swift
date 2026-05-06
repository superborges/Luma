import Foundation
import GRDB

protocol ArchiveManifestRepository: Sendable {
    func insert(_ record: ArchiveManifestRecord) throws
    func update(_ record: ArchiveManifestRecord) throws
    func delete(id: String) throws
    func fetchByExpedition(_ expeditionId: String) throws -> [ArchiveManifestRecord]
    func fetchByAlbum(_ albumId: String) throws -> [ArchiveManifestRecord]
}

final class GRDBArchiveManifestRepository: ArchiveManifestRepository, Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func insert(_ record: ArchiveManifestRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    func update(_ record: ArchiveManifestRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try ArchiveManifestRecord.deleteOne(db, key: id)
        }
    }

    func fetchByExpedition(_ expeditionId: String) throws -> [ArchiveManifestRecord] {
        try dbQueue.read { db in
            try ArchiveManifestRecord
                .filter(Column("expeditionId") == expeditionId)
                .fetchAll(db)
        }
    }

    func fetchByAlbum(_ albumId: String) throws -> [ArchiveManifestRecord] {
        try dbQueue.read { db in
            try ArchiveManifestRecord
                .filter(Column("albumId") == albumId)
                .fetchAll(db)
        }
    }
}
