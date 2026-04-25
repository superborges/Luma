import Foundation
import XCTest
@testable import Luma

final class RealFolderIntegrationTests: XCTestCase {
    func testRealFolderImportExportAndShrinkKeep() async throws {
        let context = try makeContext(prefix: "real-folder")
        try await TestFixtures.withAppSupportRootOverride(context.appSupportRoot) {
            let importManager = ImportManager()
            let exporter = FolderExporter()
            let archiver = VideoArchiver()
            let imported = try await importManager.importFromSource(
                .folder(path: context.importURL.path, displayName: context.importURL.lastPathComponent),
                progress: { _ in },
                snapshot: { _ in }
            )

            XCTAssertEqual(imported.manifest.assets.count, context.expectedImportCount)
            XCTAssertFalse(imported.manifest.groups.isEmpty)

            var assets = imported.manifest.assets
            let pickedCount = min(6, assets.count)
            for index in assets.indices {
                if index < pickedCount {
                    assets[index].userDecision = .picked
                    assets[index].aiScore = TestFixtures.makeAIScore(
                        provider: "real-folder-smoke",
                        overall: 90 - index,
                        recommended: index < 3,
                        comment: "Picked from real-folder smoke test"
                    )
                } else {
                    assets[index].userDecision = .pending
                    assets[index].aiScore = TestFixtures.makeAIScore(
                        provider: "real-folder-smoke",
                        overall: max(55, 80 - index),
                        recommended: false,
                        comment: "Archive candidate from real-folder smoke test"
                    )
                }
            }

            var exportOptions = ExportOptions.default
            exportOptions.outputPath = context.exportRoot
            exportOptions.folderTemplate = .byGroup
            exportOptions.writeXmpSidecar = true
            exportOptions.writeEditSuggestionsToXmp = false

            let exportResult = try await exporter.export(
                assets: assets,
                groups: imported.manifest.groups,
                options: exportOptions
            )
            XCTAssertEqual(exportResult.exportedCount, pickedCount)

            let archiveCandidates = assets.filter { $0.userDecision != .picked }
            let archiveResult = try await archiver.shrinkKeep(
                assets: archiveCandidates,
                batchName: context.importURL.lastPathComponent
            )

            let expectedShrinkKeepCount = archiveCandidates.filter { asset in
                guard let sourceURL = asset.previewURL ?? asset.rawURL else { return false }
                return EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 2048) != nil
            }.count
            XCTAssertEqual(archiveResult.generatedFiles.count, expectedShrinkKeepCount)
            let archiveManifestURL = archiveResult.outputDirectory.appendingPathComponent("archive_manifest.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: archiveManifestURL.path))

            let exportedFiles = try FileManager.default.subpathsOfDirectory(atPath: context.exportRoot.path)
            let exportedMediaFiles = exportedFiles.filter { exportedMediaExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            let exportedXMPs = exportedFiles.filter { $0.lowercased().hasSuffix(".xmp") }
            XCTAssertEqual(exportedMediaFiles.count, exportResult.exportedCount)
            XCTAssertEqual(exportedXMPs.count, exportResult.exportedCount)

            print("REAL_FOLDER_E2E_RUN_ROOT=\(context.runRoot.path)")
            print("REAL_FOLDER_IMPORT_COUNT=\(imported.manifest.assets.count)")
            print("REAL_FOLDER_GROUP_COUNT=\(imported.manifest.groups.count)")
            print("REAL_FOLDER_PICKED_COUNT=\(pickedCount)")
            print("REAL_FOLDER_ARCHIVE_COUNT=\(archiveResult.generatedFiles.count)")
        }
    }

    func testRealFolderImportAndArchiveVideo() async throws {
        let context = try makeContext(prefix: "real-folder-video")
        try await TestFixtures.withAppSupportRootOverride(context.appSupportRoot) {
            let importManager = ImportManager()
            let archiver = VideoArchiver()
            let imported = try await importManager.importFromSource(
                .folder(path: context.importURL.path, displayName: context.importURL.lastPathComponent),
                progress: { _ in },
                snapshot: { _ in }
            )

            XCTAssertEqual(imported.manifest.assets.count, context.expectedImportCount)
            XCTAssertFalse(imported.manifest.groups.isEmpty)

            let assetsByID = Dictionary(
                imported.manifest.assets.map { ($0.id, $0) },
                uniquingKeysWith: { _, new in new }
            )
            let preservedPerGroup = 3
            var preservedIDs = Set<UUID>()
            for group in imported.manifest.groups {
                let candidates = group.assets
                    .compactMap { assetsByID[$0] }
                    .sorted { $0.metadata.captureDate < $1.metadata.captureDate }
                for asset in candidates.suffix(preservedPerGroup) {
                    preservedIDs.insert(asset.id)
                }
            }

            var archivedAssets = imported.manifest.assets
            for index in archivedAssets.indices {
                if preservedIDs.contains(archivedAssets[index].id) {
                    archivedAssets[index].userDecision = .pending
                    archivedAssets[index].aiScore = TestFixtures.makeAIScore(
                        provider: "real-folder-video",
                        overall: max(60, 84 - index),
                        recommended: index % 2 == 0,
                        comment: "Archive video candidate from real-folder smoke test"
                    )
                } else {
                    archivedAssets[index].userDecision = .picked
                    archivedAssets[index].aiScore = TestFixtures.makeAIScore(
                        provider: "real-folder-video",
                        overall: min(95, 96 - index),
                        recommended: true,
                        comment: "Excluded from archive video smoke test"
                    )
                }
            }

            let expectedVideoGroups = imported.manifest.groups.filter { group in
                group.assets.contains { preservedIDs.contains($0) }
            }
            XCTAssertFalse(expectedVideoGroups.isEmpty)

            let archiveResult = try await archiver.archive(
                groups: imported.manifest.groups,
                assets: archivedAssets,
                batchName: "\(context.importURL.lastPathComponent)-video"
            )

            XCTAssertEqual(archiveResult.generatedFiles.count, expectedVideoGroups.count)
            XCTAssertTrue(archiveResult.generatedFiles.allSatisfy { $0.pathExtension.lowercased() == "mp4" })
            XCTAssertTrue(archiveResult.generatedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

            let archiveManifestURL = archiveResult.outputDirectory.appendingPathComponent("archive_manifest.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: archiveManifestURL.path))

            let manifestData = try Data(contentsOf: archiveManifestURL)
            let manifestJSON = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
            let videos = manifestJSON?["videos"] as? [[String: Any]]
            XCTAssertEqual(videos?.count, expectedVideoGroups.count)

            print("REAL_FOLDER_VIDEO_RUN_ROOT=\(context.runRoot.path)")
            print("REAL_FOLDER_VIDEO_IMPORT_COUNT=\(imported.manifest.assets.count)")
            print("REAL_FOLDER_VIDEO_GROUP_COUNT=\(imported.manifest.groups.count)")
            print("REAL_FOLDER_VIDEO_ARCHIVE_GROUP_COUNT=\(expectedVideoGroups.count)")
            print("REAL_FOLDER_VIDEO_FILE_COUNT=\(archiveResult.generatedFiles.count)")
        }
    }

    private func makeContext(prefix: String) throws -> RealFolderContext {
        let env = ProcessInfo.processInfo.environment
        let rawImportPath: String? = {
            for key in ["LUMA_V1_CONTRACT", "LUMA_REAL_IMPORT_PATH"] {
                if let v = env[key], !v.isEmpty { return v }
            }
            return nil
        }()
        guard let rawImportPath else {
            throw XCTSkip(
                "Set LUMA_V1_CONTRACT (V1 合约目录) 或 LUMA_REAL_IMPORT_PATH 为真实素材目录以跑本组集成测试。"
            )
        }

        let importURL = URL(fileURLWithPath: rawImportPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: importURL.path) else {
            throw XCTSkip("Real import path does not exist: \(importURL.path)")
        }

        let outputRoot: URL
        if let rawOutputRoot = ProcessInfo.processInfo.environment["LUMA_REAL_OUTPUT_ROOT"], !rawOutputRoot.isEmpty {
            outputRoot = URL(fileURLWithPath: rawOutputRoot, isDirectory: true)
        } else {
            outputRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LumaRealFolderArtifacts", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let runID = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let runRoot = outputRoot.appendingPathComponent("\(prefix)-\(runID)", isDirectory: true)
        let appSupportRoot = runRoot.appendingPathComponent("app-support", isDirectory: true)
        let exportRoot = runRoot.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let discoveredItems = try MediaFileScanner.scan(
            rootFolder: importURL,
            source: .folder(path: importURL.path)
        )
        XCTAssertFalse(discoveredItems.isEmpty)

        return RealFolderContext(
            importURL: importURL,
            expectedImportCount: discoveredItems.count,
            runRoot: runRoot,
            appSupportRoot: appSupportRoot,
            exportRoot: exportRoot
        )
    }
}

private struct RealFolderContext {
    let importURL: URL
    let expectedImportCount: Int
    let runRoot: URL
    let appSupportRoot: URL
    let exportRoot: URL
}

private let exportedMediaExtensions: Set<String> = [
    "jpg", "jpeg", "heic", "heif",
    "arw", "cr3", "nef", "raf", "dng", "orf", "rw2"
]
