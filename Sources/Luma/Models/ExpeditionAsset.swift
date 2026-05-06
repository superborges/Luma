import Foundation

struct ExpeditionAsset: Identifiable, Sendable {
    let id: UUID
    var expeditionId: UUID
    var assetId: UUID
    var addedAt: Date
    var addedBy: AssetAddedBy
    var localOrder: Int
    var decision: Decision
    var rating: Int?
    var colorLabel: String?
    var isRecommended: Bool
    var isBestInGroup: Bool
    var isUserOverride: Bool
    var isArchived: Bool
    var isHiddenInExpedition: Bool
    var updatedAt: Date

    init?(record: ExpeditionAssetRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let expId = UUID(uuidString: record.expeditionId),
              let aId = UUID(uuidString: record.assetId),
              let ab = AssetAddedBy(rawValue: record.addedBy),
              let dec = Decision(rawValue: record.decision) else {
            return nil
        }
        self.id = uuid
        self.expeditionId = expId
        self.assetId = aId
        self.addedAt = Date(timeIntervalSinceReferenceDate: record.addedAt)
        self.addedBy = ab
        self.localOrder = record.localOrder
        self.decision = dec
        self.rating = record.rating
        self.colorLabel = record.colorLabel
        self.isRecommended = record.isRecommended
        self.isBestInGroup = record.isBestInGroup
        self.isUserOverride = record.isUserOverride
        self.isArchived = record.isArchived
        self.isHiddenInExpedition = record.isHiddenInExpedition
        self.updatedAt = Date(timeIntervalSinceReferenceDate: record.updatedAt)
    }

    func toRecord() -> ExpeditionAssetRecord {
        ExpeditionAssetRecord(
            id: id.uuidString,
            expeditionId: expeditionId.uuidString,
            assetId: assetId.uuidString,
            addedAt: addedAt.timeIntervalSinceReferenceDate,
            addedBy: addedBy.rawValue,
            localOrder: localOrder,
            decision: decision.rawValue,
            rating: rating,
            colorLabel: colorLabel,
            isRecommended: isRecommended,
            isBestInGroup: isBestInGroup,
            isUserOverride: isUserOverride,
            isArchived: isArchived,
            isHiddenInExpedition: isHiddenInExpedition,
            updatedAt: updatedAt.timeIntervalSinceReferenceDate
        )
    }
}
