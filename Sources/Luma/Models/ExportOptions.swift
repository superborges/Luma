import Foundation

struct ExportOptions: Codable, Hashable {
    var destination: ExportDestination
    var createAlbumPerGroup: Bool
    var mergeRawAndJpeg: Bool
    var preserveLivePhoto: Bool
    var includeAICommentAsDescription: Bool
    var lrAutoImportFolder: URL?
    var writeXmpSidecar: Bool
    var writeEditSuggestionsToXmp: Bool
    var folderTemplate: FolderTemplate
    var outputPath: URL?
    var fileNamingRule: FileNamingRule
    var customNamingTemplate: String
    var rejectedHandling: RejectedHandling
    /// 仅对 `.photosApp` 目的地生效；源 = 照片 App 时决定是否回删未选原图。
    var photosCleanupStrategy: PhotosCleanupStrategy
    /// 试跑（dry-run）：走完全流程但跳过真实 deleteAssets 调用，仅记录意图日志。
    var photosCleanupDryRun: Bool
    /// 仅重试失败项：非 nil 时只导出 ID 命中的 picked。设为 nil（默认）= 导全部 picked。
    /// 非 Codable，运行时态。
    var onlyAssetIDs: Set<UUID>?

    static let `default` = ExportOptions(
        destination: .folder,
        createAlbumPerGroup: true,
        mergeRawAndJpeg: true,
        preserveLivePhoto: true,
        includeAICommentAsDescription: false,
        lrAutoImportFolder: nil,
        writeXmpSidecar: true,
        writeEditSuggestionsToXmp: false,
        folderTemplate: .byDate,
        outputPath: nil,
        fileNamingRule: .original,
        customNamingTemplate: "{date}_{original}",
        rejectedHandling: .archiveVideo,
        photosCleanupStrategy: .keepOriginals,
        photosCleanupDryRun: false
    )

    private enum CodingKeys: String, CodingKey {
        case destination
        case createAlbumPerGroup
        case mergeRawAndJpeg
        case preserveLivePhoto
        case includeAICommentAsDescription
        case lrAutoImportFolder
        case writeXmpSidecar
        case writeEditSuggestionsToXmp
        case folderTemplate
        case outputPath
        case fileNamingRule
        case customNamingTemplate
        case rejectedHandling
        case photosCleanupStrategy
        case photosCleanupDryRun
    }

    init(
        destination: ExportDestination,
        createAlbumPerGroup: Bool,
        mergeRawAndJpeg: Bool,
        preserveLivePhoto: Bool,
        includeAICommentAsDescription: Bool,
        lrAutoImportFolder: URL?,
        writeXmpSidecar: Bool,
        writeEditSuggestionsToXmp: Bool,
        folderTemplate: FolderTemplate,
        outputPath: URL?,
        fileNamingRule: FileNamingRule = .original,
        customNamingTemplate: String = "{date}_{original}",
        rejectedHandling: RejectedHandling,
        photosCleanupStrategy: PhotosCleanupStrategy = .keepOriginals,
        photosCleanupDryRun: Bool = false
    ) {
        self.destination = destination
        self.createAlbumPerGroup = createAlbumPerGroup
        self.mergeRawAndJpeg = mergeRawAndJpeg
        self.preserveLivePhoto = preserveLivePhoto
        self.includeAICommentAsDescription = includeAICommentAsDescription
        self.lrAutoImportFolder = lrAutoImportFolder
        self.writeXmpSidecar = writeXmpSidecar
        self.writeEditSuggestionsToXmp = writeEditSuggestionsToXmp
        self.folderTemplate = folderTemplate
        self.outputPath = outputPath
        self.fileNamingRule = fileNamingRule
        self.customNamingTemplate = customNamingTemplate
        self.rejectedHandling = rejectedHandling
        self.photosCleanupStrategy = photosCleanupStrategy
        self.photosCleanupDryRun = photosCleanupDryRun
        self.onlyAssetIDs = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destination = try container.decode(ExportDestination.self, forKey: .destination)
        createAlbumPerGroup = try container.decode(Bool.self, forKey: .createAlbumPerGroup)
        mergeRawAndJpeg = try container.decode(Bool.self, forKey: .mergeRawAndJpeg)
        preserveLivePhoto = try container.decode(Bool.self, forKey: .preserveLivePhoto)
        includeAICommentAsDescription = try container.decode(Bool.self, forKey: .includeAICommentAsDescription)
        lrAutoImportFolder = try container.decodeIfPresent(URL.self, forKey: .lrAutoImportFolder)
        writeXmpSidecar = try container.decode(Bool.self, forKey: .writeXmpSidecar)
        writeEditSuggestionsToXmp = try container.decode(Bool.self, forKey: .writeEditSuggestionsToXmp)
        folderTemplate = try container.decode(FolderTemplate.self, forKey: .folderTemplate)
        outputPath = try container.decodeIfPresent(URL.self, forKey: .outputPath)
        fileNamingRule = try container.decodeIfPresent(FileNamingRule.self, forKey: .fileNamingRule) ?? .original
        customNamingTemplate = try container.decodeIfPresent(String.self, forKey: .customNamingTemplate) ?? "{date}_{original}"
        rejectedHandling = try container.decode(RejectedHandling.self, forKey: .rejectedHandling)
        photosCleanupStrategy = try container.decodeIfPresent(PhotosCleanupStrategy.self, forKey: .photosCleanupStrategy) ?? .keepOriginals
        photosCleanupDryRun = try container.decodeIfPresent(Bool.self, forKey: .photosCleanupDryRun) ?? false
        onlyAssetIDs = nil
    }
}

enum ExportDestination: String, Codable, Hashable, CaseIterable, Identifiable {
    case photosApp
    case lightroom
    case folder

    var id: String { rawValue }
}

enum FolderTemplate: String, Codable, Hashable, CaseIterable, Identifiable {
    case byDate
    case byGroup
    case byRating

    var id: String { rawValue }
}

enum RejectedHandling: String, Codable, Hashable, CaseIterable, Identifiable {
    case archiveVideo
    case shrinkKeep
    case discard

    var id: String { rawValue }
}

enum FileNamingRule: String, Codable, Hashable, CaseIterable, Identifiable {
    case original
    case datePrefix
    case custom

    var id: String { rawValue }
}

/// 导出到照片 App 时对「源自照片库」的未选原图的清理策略。
/// - `keepOriginals`：仅新建相册装 Picked，**原图全部保留**（最安全）。
/// - `deleteRejectedOriginals`：Picked 入相册后，对 Rejected 原图发起系统删除请求，
///   **系统会弹原生对话框由用户最终确认**（Apple 强制，Luma 不能也不会绕过）。
enum PhotosCleanupStrategy: String, Codable, Hashable, CaseIterable, Identifiable {
    case keepOriginals
    case deleteRejectedOriginals

    var id: String { rawValue }
}
