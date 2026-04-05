import Foundation

struct ProjectManifest: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var assets: [MediaAsset]
    var groups: [PhotoGroup]
}
