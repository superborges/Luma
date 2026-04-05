import Foundation

struct PhotoGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var assets: [UUID]
    var subGroups: [SubGroup]
    let timeRange: ClosedRange<Date>
    let location: Coordinate?
    var groupComment: String?
    var recommendedAssets: [UUID]
}

struct SubGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var assets: [UUID]
    var bestAsset: UUID?
}
