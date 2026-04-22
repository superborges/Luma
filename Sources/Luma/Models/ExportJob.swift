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
    /// 可选：清理掉的源相册原图数（仅 Photos App 路径）。
    var cleanedCount: Int?
    /// 可选：用户取消清理张数。
    var cleanupCancelledCount: Int?
    /// 可选：写入相册名 / 目录路径的简短描述。
    var albumDescription: String?
    /// 可选：失败明细（精简到 ID + 原因），用于"仅重试失败项"复用。
    var failures: [ExportFailure]?
}
