import Foundation

struct LightroomExporter: ExportDestinationAdapter {
    var displayName: String {
        "Lightroom Classic"
    }

    func validateConfiguration(options: ExportOptions) async throws -> Bool {
        options.lrAutoImportFolder != nil
    }

    func export(assets: [MediaAsset], groups: [PhotoGroup], options: ExportOptions) async throws -> ExportResult {
        guard let outputFolder = options.lrAutoImportFolder else {
            throw LumaError.unsupported("Lightroom export requires an auto-import folder.")
        }

        var folderOptions = options
        folderOptions.outputPath = outputFolder
        // Lightroom 始终需要 XMP sidecar（评分、标签、修图建议都通过 XMP 传递）。
        folderOptions.writeXmpSidecar = true
        return try await FolderExporter().export(assets: assets, groups: groups, options: folderOptions)
    }
}
