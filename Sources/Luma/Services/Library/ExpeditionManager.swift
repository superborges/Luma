import Foundation
import GRDB

final class ExpeditionManager: Sendable {
    private let repo: any ExpeditionRepository

    init(repo: any ExpeditionRepository) {
        self.repo = repo
    }

    func createExpedition(
        name: String,
        subtitle: String? = nil,
        sourceMode: ExpeditionSourceMode
    ) throws -> Expedition {
        let now = Date().timeIntervalSinceReferenceDate
        let isMacPhotos = (sourceMode == .macPhotos)
        let record = ExpeditionRecord(
            id: UUID().uuidString,
            name: name,
            subtitle: subtitle,
            description: nil,
            coverAssetId: nil,
            startDate: nil,
            endDate: nil,
            sourceMode: sourceMode.rawValue,
            status: ExpeditionStatus.reviewing.rawValue,
            isMacPhotos: isMacPhotos,
            createdAt: now,
            updatedAt: now
        )
        try repo.insert(record)
        guard let expedition = Expedition(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct Expedition from newly created record")
        }
        return expedition
    }

    func createExpedition(
        name: String,
        subtitle: String? = nil,
        sourceMode: ExpeditionSourceMode,
        status: ExpeditionStatus,
        startDate: Date?,
        endDate: Date?,
        coverAssetId: UUID?,
        createdAt: Date,
        isMacPhotos: Bool
    ) throws -> Expedition {
        let record = ExpeditionRecord(
            id: UUID().uuidString,
            name: name,
            subtitle: subtitle,
            description: nil,
            coverAssetId: coverAssetId?.uuidString,
            startDate: startDate?.timeIntervalSinceReferenceDate,
            endDate: endDate?.timeIntervalSinceReferenceDate,
            sourceMode: sourceMode.rawValue,
            status: status.rawValue,
            isMacPhotos: isMacPhotos,
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            updatedAt: Date().timeIntervalSinceReferenceDate
        )
        try repo.insert(record)
        guard let expedition = Expedition(record: record) else {
            throw LumaError.persistenceFailed("Failed to construct Expedition from newly created record")
        }
        return expedition
    }

    func updateExpedition(_ expedition: Expedition) throws {
        var record = expedition.toRecord()
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try repo.update(record)
    }

    func deleteExpedition(_ id: UUID) throws {
        if let record = try repo.fetchById(id.uuidString), record.isMacPhotos {
            throw LumaError.persistenceFailed("系统级 Mac Photos Expedition 不可删除")
        }
        try repo.delete(id: id.uuidString)
    }

    func listExpeditions() throws -> [Expedition] {
        try repo.fetchAll().compactMap { Expedition(record: $0) }
    }

    func fetchExpedition(id: UUID) throws -> Expedition? {
        try repo.fetchById(id.uuidString).flatMap { Expedition(record: $0) }
    }

    func setExpeditionCover(expeditionId: UUID, assetId: UUID) throws {
        guard var record = try repo.fetchById(expeditionId.uuidString) else { return }
        record.coverAssetId = assetId.uuidString
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try repo.update(record)
    }

    func updateExpeditionStatus(expeditionId: UUID, status: ExpeditionStatus) throws {
        guard var record = try repo.fetchById(expeditionId.uuidString) else { return }
        record.status = status.rawValue
        record.updatedAt = Date().timeIntervalSinceReferenceDate
        try repo.update(record)
    }
}
