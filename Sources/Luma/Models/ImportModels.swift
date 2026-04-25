import Foundation

struct DiscoveredItem: Identifiable, Codable, Hashable {
    let id: UUID
    let resumeKey: String
    let baseName: String
    let source: ImportSource
    let previewFile: URL?
    let rawFile: URL?
    let auxiliaryFile: URL?
    let depthData: Bool
    let metadata: EXIFData
    let mediaType: MediaType
}

extension Array where Element == DiscoveredItem {
    /// 按 `resumeKey` 建索引。枚举层若出现重复 key，**后出现的项覆盖先出现的**（与 `ImportManager` 中曾用
    /// `uniqueKeysWithValues` 时的 trap 不同，此策略不崩溃，且便于用「列表顺序」定胜负）。
    func dictionaryByResumeKeyLastWins() -> [String: DiscoveredItem] {
        Dictionary(map { ($0.resumeKey, $0) }, uniquingKeysWith: { _, new in new })
    }
}

enum ConnectionState: String, Codable, Hashable {
    case connected
    case disconnected
    case scanning
    case unavailable
}

enum ImportPhase: String, Codable, Hashable {
    case scanning
    case preparingThumbnails
    case copyingPreviews
    case copyingOriginals
    case paused
    case finalizing
}

struct ImportProgress: Codable, Hashable {
    var phase: ImportPhase
    var completed: Int
    var total: Int
    var currentItemName: String?

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
