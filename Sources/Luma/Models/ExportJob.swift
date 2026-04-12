import Foundation

enum ExportJobStatus: String, Codable, Hashable {
    case queued
    case running
    case completed
    case failed
}

struct ExportJob: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: Date
    var completedAt: Date?
    var status: ExportJobStatus
    var options: ExportOptions
    var targetAssetIDs: [UUID]
    var exportedCount: Int
    var totalCount: Int
    var speedBytesPerSecond: Double?
    var estimatedSecondsRemaining: Double?
    var destinationDescription: String?
    var lastError: String?
}
