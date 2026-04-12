import Foundation

enum EditingSessionStatus: String, Codable, Hashable {
    case initializing
    case active
    case completed
}

struct EditingSession: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var status: EditingSessionStatus
    var targetAssetIDs: [UUID]
    var completedCount: Int
    var aiEnhancementEnabled: Bool
}
