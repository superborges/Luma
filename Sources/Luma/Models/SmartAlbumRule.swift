import Foundation

struct SmartAlbumRule: Codable, Sendable {
    var scope: SmartAlbumScope
    var filters: [SmartAlbumFilter]
}

enum SmartAlbumScope: Codable, Sendable {
    case library
    case expedition(UUID)

    private enum CodingKeys: String, CodingKey {
        case type, expeditionId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .library:
            try container.encode("library", forKey: .type)
        case .expedition(let id):
            try container.encode("expedition", forKey: .type)
            try container.encode(id, forKey: .expeditionId)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "expedition":
            let id = try container.decode(UUID.self, forKey: .expeditionId)
            self = .expedition(id)
        default:
            self = .library
        }
    }
}

enum SmartAlbumFilter: String, Codable, Sendable, CaseIterable {
    case allPicked
    case allRejected
    case highScore
    case cleanupCandidates
    case unreviewed
    case archived

    var displayName: String {
        switch self {
        case .allPicked: return "已选"
        case .allRejected: return "未选"
        case .highScore: return "高分"
        case .cleanupCandidates: return "可清理"
        case .unreviewed: return "未审"
        case .archived: return "已归档"
        }
    }

    var systemImage: String {
        switch self {
        case .allPicked: return "checkmark.circle"
        case .allRejected: return "xmark.circle"
        case .highScore: return "star.fill"
        case .cleanupCandidates: return "trash"
        case .unreviewed: return "questionmark.circle"
        case .archived: return "archivebox"
        }
    }
}
