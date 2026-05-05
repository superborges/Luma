import Foundation

enum ImportSourceDescriptor: Codable, Hashable, Identifiable {
    case folder(path: String, displayName: String)
    case sdCard(volumePath: String, displayName: String)
    case iPhone(deviceID: String, deviceName: String)
    /// Mac · 照片 App。`albumLocalIdentifier` 为 nil 时表示读取整库（按 limit 取最近 N 张）。
    /// 仅读取本地已缓存版本，不触发 iCloud 下载。
    case photosLibrary(albumLocalIdentifier: String?, limit: Int, displayName: String)

    var id: String {
        stableID
    }

    var stableID: String {
        switch self {
        case .folder(let path, _):
            return "folder:\(path)"
        case .sdCard(let volumePath, _):
            return "sd:\(volumePath)"
        case .iPhone(let deviceID, _):
            return "iphone:\(deviceID)"
        case .photosLibrary(let albumLocalIdentifier, let limit, _):
            return "photos:\(albumLocalIdentifier ?? "all"):\(limit)"
        }
    }

    var displayName: String {
        switch self {
        case .folder(_, let displayName):
            return displayName
        case .sdCard(_, let displayName):
            return displayName
        case .iPhone(_, let deviceName):
            return deviceName
        case .photosLibrary(_, _, let displayName):
            return displayName
        }
    }

    var suggestedProjectName: String {
        displayName
    }

    var importSource: ImportSource {
        switch self {
        case .folder(let path, _):
            return .folder(path: path)
        case .sdCard(let volumePath, _):
            return .sdCard(volumePath: volumePath)
        case .iPhone(let deviceID, _):
            return .iPhone(deviceID: deviceID)
        case .photosLibrary:
            // photosLibrary 源里每张资产的 source 由 adapter 在 enumerate 时按 PHAsset.localIdentifier 单独构造。
            // 这里返回一个占位值；不应被实际使用。
            return .photosLibrary(localIdentifier: "")
        }
    }
}

enum ImportSessionStatus: String, Codable, Hashable {
    case pending
    case running
    case paused
    case completed
    case failed
}

/// In-flight import checkpoint (disk) and completed import history (inside `Session`).
struct ImportSession: Codable, Identifiable, Hashable {
    let id: UUID
    var source: ImportSourceDescriptor
    /// Set while a recoverable checkpoint exists on disk; omitted from session manifest when `nil`.
    var projectDirectory: URL?
    var projectName: String?
    var createdAt: Date
    var updatedAt: Date
    var phase: ImportPhase
    var status: ImportSessionStatus
    var totalItems: Int
    var completedThumbnails: Int
    var completedPreviews: Int
    var completedOriginals: Int
    var lastError: String?
    var completedAt: Date?
    var importedAssetIDs: [UUID]

    var displayProjectName: String {
        projectName ?? source.displayName
    }

    var progressSummary: String {
        switch phase {
        case .scanning:
            return "扫描素材中"
        case .preparingThumbnails:
            return "准备缩略图 \(completedThumbnails)/\(max(totalItems, 1))"
        case .copyingPreviews:
            return "拷贝预览图 \(completedPreviews)/\(max(totalItems, 1))"
        case .copyingOriginals:
            return "拷贝原图 \(completedOriginals)/\(max(totalItems, 1))"
        case .paused:
            return lastError ?? "导入已暂停"
        case .finalizing:
            return "整理项目中"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case projectDirectory
        case projectName
        case createdAt
        case updatedAt
        case phase
        case status
        case totalItems
        case completedThumbnails
        case completedPreviews
        case completedOriginals
        case lastError
        case completedAt
        case importedAssetIDs
    }

    init(
        id: UUID,
        source: ImportSourceDescriptor,
        projectDirectory: URL?,
        projectName: String?,
        createdAt: Date,
        updatedAt: Date,
        phase: ImportPhase,
        status: ImportSessionStatus,
        totalItems: Int,
        completedThumbnails: Int,
        completedPreviews: Int,
        completedOriginals: Int,
        lastError: String?,
        completedAt: Date?,
        importedAssetIDs: [UUID]
    ) {
        self.id = id
        self.source = source
        self.projectDirectory = projectDirectory
        self.projectName = projectName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.status = status
        self.totalItems = totalItems
        self.completedThumbnails = completedThumbnails
        self.completedPreviews = completedPreviews
        self.completedOriginals = completedOriginals
        self.lastError = lastError
        self.completedAt = completedAt
        self.importedAssetIDs = importedAssetIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(ImportSourceDescriptor.self, forKey: .source)
        projectDirectory = try container.decodeIfPresent(URL.self, forKey: .projectDirectory)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        phase = try container.decode(ImportPhase.self, forKey: .phase)
        status = try container.decode(ImportSessionStatus.self, forKey: .status)
        totalItems = try container.decode(Int.self, forKey: .totalItems)
        completedThumbnails = try container.decode(Int.self, forKey: .completedThumbnails)
        completedPreviews = try container.decode(Int.self, forKey: .completedPreviews)
        completedOriginals = try container.decode(Int.self, forKey: .completedOriginals)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        importedAssetIDs = try container.decodeIfPresent([UUID].self, forKey: .importedAssetIDs) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(projectDirectory, forKey: .projectDirectory)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(phase, forKey: .phase)
        try container.encode(status, forKey: .status)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(completedThumbnails, forKey: .completedThumbnails)
        try container.encode(completedPreviews, forKey: .completedPreviews)
        try container.encode(completedOriginals, forKey: .completedOriginals)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(importedAssetIDs, forKey: .importedAssetIDs)
    }
}

/// SD 卡快速扫描汇总（附在导入提示弹窗上）。
struct SDCardScanInfo: Hashable, Sendable {
    let photoCount: Int
    let rawFormatSummary: String

    init(photoCount: Int, rawFormatSummary: String) {
        self.photoCount = photoCount
        self.rawFormatSummary = rawFormatSummary
    }

    init(summary: DCIMScanner.Summary) {
        self.photoCount = summary.photoCount
        if summary.rawFormatDistribution.isEmpty {
            rawFormatSummary = ""
        } else {
            let parts = summary.rawFormatDistribution
                .sorted { $0.value > $1.value }
                .map { "\($0.key) ×\($0.value)" }
            rawFormatSummary = parts.joined(separator: "、")
        }
    }
}

enum PendingImportPrompt: Hashable, Identifiable {
    case importSource(ImportSourceDescriptor)
    case sdCardImport(ImportSourceDescriptor, SDCardScanInfo)
    case resumeSession(ImportSession)

    var id: String {
        switch self {
        case .importSource(let source):
            return "import:\(source.stableID)"
        case .sdCardImport(let source, _):
            return "import:\(source.stableID)"
        case .resumeSession(let session):
            return "resume:\(session.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .importSource:
            return "检测到可导入设备"
        case .sdCardImport:
            return "检测到 SD 卡"
        case .resumeSession:
            return "发现未完成的导入"
        }
    }

    var message: String {
        switch self {
        case .importSource(let source):
            return "检测到 \(source.displayName)，是否立即开始导入？"
        case .sdCardImport(let source, let info):
            if info.photoCount == 0 {
                return "\(source.displayName) 中未检测到照片（需要 DCIM 目录）。"
            }
            var msg = "检测到 \(source.displayName)，共 \(info.photoCount) 张照片。"
            if !info.rawFormatSummary.isEmpty {
                msg += "\nRAW 格式：\(info.rawFormatSummary)"
            }
            return msg
        case .resumeSession(let session):
            return "\u{201C}\(session.displayProjectName)\u{201D} 还有未完成的导入。\n\(session.progressSummary)"
        }
    }

    var confirmTitle: String {
        switch self {
        case .importSource:
            return "开始导入"
        case .sdCardImport(_, let info):
            return info.photoCount > 0 ? "开始导入" : "好"
        case .resumeSession:
            return "继续导入"
        }
    }

    /// SD 卡无照片时不允许导入。
    var isActionable: Bool {
        switch self {
        case .sdCardImport(_, let info):
            return info.photoCount > 0
        default:
            return true
        }
    }
}
