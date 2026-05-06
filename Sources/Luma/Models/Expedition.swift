import Foundation

struct Expedition: Identifiable, Sendable {
    let id: UUID
    var name: String
    var subtitle: String?
    var description: String?
    var coverAssetId: UUID?
    var startDate: Date?
    var endDate: Date?
    var sourceMode: ExpeditionSourceMode
    var status: ExpeditionStatus
    var isMacPhotos: Bool
    var createdAt: Date
    var updatedAt: Date

    init?(record: ExpeditionRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let sm = ExpeditionSourceMode(rawValue: record.sourceMode),
              let st = ExpeditionStatus(rawValue: record.status) else {
            return nil
        }
        self.id = uuid
        self.name = record.name
        self.subtitle = record.subtitle
        self.description = record.description
        self.coverAssetId = record.coverAssetId.flatMap { UUID(uuidString: $0) }
        self.startDate = record.startDate.map { Date(timeIntervalSinceReferenceDate: $0) }
        self.endDate = record.endDate.map { Date(timeIntervalSinceReferenceDate: $0) }
        self.sourceMode = sm
        self.status = st
        self.isMacPhotos = record.isMacPhotos
        self.createdAt = Date(timeIntervalSinceReferenceDate: record.createdAt)
        self.updatedAt = Date(timeIntervalSinceReferenceDate: record.updatedAt)
    }

    func toRecord() -> ExpeditionRecord {
        ExpeditionRecord(
            id: id.uuidString,
            name: name,
            subtitle: subtitle,
            description: description,
            coverAssetId: coverAssetId?.uuidString,
            startDate: startDate?.timeIntervalSinceReferenceDate,
            endDate: endDate?.timeIntervalSinceReferenceDate,
            sourceMode: sourceMode.rawValue,
            status: status.rawValue,
            isMacPhotos: isMacPhotos,
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            updatedAt: updatedAt.timeIntervalSinceReferenceDate
        )
    }
}
