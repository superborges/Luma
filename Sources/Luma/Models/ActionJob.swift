import Foundation

private let _actionJobDecoder = JSONDecoder()
private let _actionJobEncoder = JSONEncoder()

enum ActionKind: String, Codable, Sendable {
    case archiveVideo
    case archiveLowres
    case archiveMarkerOnly
    case exportToFolder
    case syncAlbumToPhotos
}

enum JobStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled

    init(rawValueCompat raw: String) {
        switch raw {
        case "queued": self = .pending
        default: self = JobStatus(rawValue: raw) ?? .pending
        }
    }
}

struct ActionJob: Identifiable, Sendable {
    let id: UUID
    var expeditionId: UUID?
    var albumId: UUID?
    var kind: ActionKind
    var targetAssetIds: [UUID]
    var status: JobStatus
    var createdAt: Date
    var completedAt: Date?
    var resultURL: URL?
    var errorMessage: String?

    init?(record: ActionJobRecord) {
        guard let uuid = UUID(uuidString: record.id),
              let kind = ActionKind(rawValue: record.kind) else {
            return nil
        }
        self.id = uuid
        self.expeditionId = record.expeditionId.flatMap { UUID(uuidString: $0) }
        self.albumId = record.albumId.flatMap { UUID(uuidString: $0) }
        self.kind = kind
        self.targetAssetIds = Self.decodeAssetIds(record.targetAssetIdsJSON)
        self.status = JobStatus(rawValueCompat: record.status)
        self.createdAt = Date(timeIntervalSinceReferenceDate: record.createdAt)
        self.completedAt = record.completedAt.map { Date(timeIntervalSinceReferenceDate: $0) }
        self.resultURL = record.resultURL.flatMap { URL(string: $0) }
        self.errorMessage = record.errorMessage
    }

    func toRecord() -> ActionJobRecord {
        ActionJobRecord(
            id: id.uuidString,
            expeditionId: expeditionId?.uuidString,
            albumId: albumId?.uuidString,
            kind: kind.rawValue,
            targetAssetIdsJSON: Self.encodeAssetIds(targetAssetIds),
            status: status.rawValue,
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            completedAt: completedAt?.timeIntervalSinceReferenceDate,
            resultURL: resultURL?.absoluteString,
            errorMessage: errorMessage
        )
    }

    private static func decodeAssetIds(_ json: String?) -> [UUID] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? _actionJobDecoder.decode([String].self, from: data) else {
            return []
        }
        return arr.compactMap { UUID(uuidString: $0) }
    }

    static func encodeAssetIds(_ ids: [UUID]) -> String? {
        guard !ids.isEmpty else { return nil }
        let arr = ids.map(\.uuidString)
        guard let data = try? _actionJobEncoder.encode(arr) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
