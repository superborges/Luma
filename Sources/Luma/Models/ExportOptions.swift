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
    var rejectedHandling: RejectedHandling

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
        rejectedHandling: .archiveVideo
    )
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
