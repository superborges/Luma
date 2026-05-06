import Foundation

enum AssetSourceKind: String, Codable, Hashable, Sendable {
    case sdCard
    case localFolder
    case macPhotos
}

enum AssetStorageMode: String, Codable, Hashable, Sendable {
    /// Luma copies the file into managed-originals/
    case managed
    /// Luma only stores a reference to the original path
    case referenced
    /// Mac Photos: Luma never holds the file, uses PhotoKit to fetch on demand
    case externalReference
}

enum ExpeditionSourceMode: String, Codable, Hashable, Sendable {
    case sdCard
    case localFolder
    case macPhotos
    case mixed
}

enum ExpeditionStatus: String, Codable, Hashable, Sendable {
    case importing
    case analyzing
    case reviewing
    case completed
    case archived
}

enum AssetAddedBy: Codable, Hashable, Sendable {
    case importSession(String)
    case manualAdd
    case macPhotosSync

    var rawValue: String {
        switch self {
        case .importSession(let id): return "importSession:\(id)"
        case .manualAdd: return "manualAdd"
        case .macPhotosSync: return "macPhotosSync"
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix("importSession:") {
            let id = String(rawValue.dropFirst("importSession:".count))
            self = .importSession(id)
        } else if rawValue == "manualAdd" {
            self = .manualAdd
        } else if rawValue == "macPhotosSync" {
            self = .macPhotosSync
        } else {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = AssetAddedBy(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid AssetAddedBy: \(raw)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
