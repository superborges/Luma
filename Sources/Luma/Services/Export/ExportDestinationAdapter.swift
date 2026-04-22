import Foundation

protocol ExportDestinationAdapter: Sendable {
    var displayName: String { get }
    func export(assets: [MediaAsset], groups: [PhotoGroup], options: ExportOptions) async throws -> ExportResult
    func validateConfiguration(options: ExportOptions) async throws -> Bool
}

struct ExportResult: Codable, Hashable {
    let exportedCount: Int
    let skippedCount: Int
    let destinationDescription: String
    /// 仅导出目标 = 照片 App 且启用了清理策略时非零：被系统对话框确认删除的原图数量。
    let cleanedCount: Int
    /// 用户在系统对话框点击"取消"的清理张数（仅 Photos App 路径有意义）。
    let cleanupCancelledCount: Int
    /// 单个文件级失败明细：assetID → reason。供"仅重试失败项"使用。
    let failures: [ExportFailure]
    /// 给摘要展示用：Photos App 路径下实际写入的相册名（默认 = Session 名 / 各分组名）。
    let albumDescription: String?
    /// 目标目录（仅 Folder/Lightroom 有效），用于"在访达中显示"。
    let destinationURL: URL?

    init(
        exportedCount: Int,
        skippedCount: Int,
        destinationDescription: String,
        cleanedCount: Int = 0,
        cleanupCancelledCount: Int = 0,
        failures: [ExportFailure] = [],
        albumDescription: String? = nil,
        destinationURL: URL? = nil
    ) {
        self.exportedCount = exportedCount
        self.skippedCount = skippedCount
        self.destinationDescription = destinationDescription
        self.cleanedCount = cleanedCount
        self.cleanupCancelledCount = cleanupCancelledCount
        self.failures = failures
        self.albumDescription = albumDescription
        self.destinationURL = destinationURL
    }

    var failedCount: Int { failures.count }

    private enum CodingKeys: String, CodingKey {
        case exportedCount
        case skippedCount
        case destinationDescription
        case cleanedCount
        case cleanupCancelledCount
        case failures
        case albumDescription
        case destinationURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exportedCount = try c.decode(Int.self, forKey: .exportedCount)
        skippedCount = try c.decode(Int.self, forKey: .skippedCount)
        destinationDescription = try c.decode(String.self, forKey: .destinationDescription)
        cleanedCount = try c.decodeIfPresent(Int.self, forKey: .cleanedCount) ?? 0
        cleanupCancelledCount = try c.decodeIfPresent(Int.self, forKey: .cleanupCancelledCount) ?? 0
        failures = try c.decodeIfPresent([ExportFailure].self, forKey: .failures) ?? []
        albumDescription = try c.decodeIfPresent(String.self, forKey: .albumDescription)
        destinationURL = try c.decodeIfPresent(URL.self, forKey: .destinationURL)
    }
}

/// 单文件失败明细。`assetID` 用于"仅重试失败项"过滤；`fileName/reason` 仅用于 UI 展示。
struct ExportFailure: Codable, Hashable, Identifiable {
    var id: UUID { assetID }
    let assetID: UUID
    let fileName: String
    let reason: String
}
