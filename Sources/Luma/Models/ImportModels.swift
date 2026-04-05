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
