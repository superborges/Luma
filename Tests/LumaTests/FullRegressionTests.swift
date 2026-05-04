import Foundation
import XCTest
@testable import Luma

// MARK: - Shared context

/// 环境变量驱动的真实目录端到端回归测试。
/// 缺少任一环境变量时所有 test case 自动 XCTSkip，不影响 CI。
final class FullRegressionTests: XCTestCase {

    private func requireSD() throws -> E2EContext {
        do {
            return try E2EContext.make(sourceEnvKey: "LUMA_E2E_SD_PATH", prefix: "sd")
        } catch is E2ESetupError {
            throw XCTSkip("Set LUMA_E2E_SD_PATH to run SD regression tests")
        }
    }

    private func requirePhoto() throws -> E2EContext {
        do {
            return try E2EContext.make(sourceEnvKey: "LUMA_E2E_PHOTO_PATH", prefix: "photo")
        } catch is E2ESetupError {
            throw XCTSkip("Set LUMA_E2E_PHOTO_PATH to run Photo regression tests")
        }
    }

    // MARK: - Phase 1: SD 导入链路

    func testSDImport() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()

            XCTAssertEqual(imported.manifest.assets.count, ctx.expectedImportCount,
                           "SD 导入张数应 == MediaFileScanner 预扫结果 (\(ctx.expectedImportCount))")
            XCTAssertFalse(imported.manifest.groups.isEmpty, "导入后至少有 1 个分组")

            let allHavePreview = imported.manifest.assets.allSatisfy { $0.primaryDisplayURL != nil }
            XCTAssertTrue(allHavePreview, "每张 asset 都应有可显示的 URL")

            printSummary("SD_IMPORT", [
                "assets": imported.manifest.assets.count,
                "groups": imported.manifest.groups.count,
            ])
        }
    }

    func testSDGrouping() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            let engine = GroupingEngine()
            let groups = await engine.makeGroups(from: imported.manifest.assets, resolvesLocationNames: false)

            XCTAssertFalse(groups.isEmpty)
            for group in groups {
                XCTAssertFalse(group.assets.isEmpty, "组 '\(group.name)' 不应为空")
                XCTAssertFalse(group.subGroups.isEmpty, "组 '\(group.name)' 应有子组")
            }

            let totalAssetsInGroups = groups.reduce(0) { $0 + $1.assets.count }
            XCTAssertEqual(totalAssetsInGroups, imported.manifest.assets.count,
                           "分组后 asset 总数应与导入一致")

            printSummary("SD_GROUPING", [
                "groups": groups.count,
                "subgroups": groups.reduce(0) { $0 + $1.subGroups.count },
            ])
        }
    }

    func testSDLocalScoring() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            let scorer = LocalMLScorer()
            let sampled = Array(imported.manifest.assets.prefix(5))

            for asset in sampled {
                let assessment = await scorer.score(asset: asset)
                XCTAssertTrue((0...100).contains(assessment.score),
                              "score 应在 0-100，实际 \(assessment.score) for \(asset.baseName)")
                XCTAssertTrue((0...100).contains(assessment.subscores.composition))
                XCTAssertTrue((0...100).contains(assessment.subscores.exposure))
                XCTAssertFalse(assessment.comment.isEmpty, "comment 不应为空")
            }

            printSummary("SD_LOCAL_SCORING", [
                "sampled": sampled.count,
            ])
        }
    }

    // MARK: - Phase 2: Photo 目录导入链路

    func testPhotoImport() async throws {
        let ctx = try requirePhoto()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()

            XCTAssertEqual(imported.manifest.assets.count, ctx.expectedImportCount,
                           "Photo 导入张数应 == MediaFileScanner 预扫结果 (\(ctx.expectedImportCount))")
            XCTAssertFalse(imported.manifest.groups.isEmpty)

            printSummary("PHOTO_IMPORT", [
                "assets": imported.manifest.assets.count,
                "groups": imported.manifest.groups.count,
            ])
        }
    }

    func testPhotoGrouping() async throws {
        let ctx = try requirePhoto()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            let engine = GroupingEngine()
            let groups = await engine.makeGroups(from: imported.manifest.assets, resolvesLocationNames: false)

            XCTAssertFalse(groups.isEmpty)
            let totalAssetsInGroups = groups.reduce(0) { $0 + $1.assets.count }
            XCTAssertEqual(totalAssetsInGroups, imported.manifest.assets.count)

            printSummary("PHOTO_GROUPING", [
                "groups": groups.count,
                "assets_in_groups": totalAssetsInGroups,
            ])
        }
    }

    // MARK: - Phase 3: 导出变体

    func testExportByGroupWithXMP() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            var assets = imported.manifest.assets
            let pickedCount = min(6, assets.count)
            for i in 0..<pickedCount {
                assets[i].userDecision = .picked
                assets[i].aiScore = TestFixtures.makeAIScore(
                    provider: "e2e-regression", overall: 90 - i, recommended: i < 3
                )
            }

            let exportRoot = ctx.exportRoot.appendingPathComponent("byGroup", isDirectory: true)
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

            var options = ExportOptions.default
            options.outputPath = exportRoot
            options.folderTemplate = .byGroup
            options.writeXmpSidecar = true

            let exporter = FolderExporter()
            let result = try await exporter.export(
                assets: assets, groups: imported.manifest.groups, options: options
            )

            XCTAssertEqual(result.exportedCount, pickedCount)

            let exportedFiles = try FileManager.default.subpathsOfDirectory(atPath: exportRoot.path)
            let mediaFiles = exportedFiles.filter { mediaExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            let xmpFiles = exportedFiles.filter { $0.lowercased().hasSuffix(".xmp") }

            XCTAssertEqual(mediaFiles.count, pickedCount)
            XCTAssertEqual(xmpFiles.count, pickedCount, "每张导出的照片都应有对应 XMP")

            for xmpRelPath in xmpFiles {
                let xmpURL = exportRoot.appendingPathComponent(xmpRelPath)
                let content = try String(contentsOf: xmpURL, encoding: .utf8)
                XCTAssertTrue(content.contains("x:xmpmeta"), "XMP 应包含有效 XML 元数据")
            }

            printSummary("EXPORT_BY_GROUP", [
                "exported": result.exportedCount,
                "xmp_count": xmpFiles.count,
            ])
        }
    }

    func testExportByDateWithDatePrefix() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            var assets = imported.manifest.assets
            let pickedCount = min(4, assets.count)
            for i in 0..<pickedCount {
                assets[i].userDecision = .picked
            }

            let exportRoot = ctx.exportRoot.appendingPathComponent("byDate", isDirectory: true)
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

            var options = ExportOptions.default
            options.outputPath = exportRoot
            options.folderTemplate = .byDate
            options.fileNamingRule = .datePrefix
            options.writeXmpSidecar = false

            let exporter = FolderExporter()
            let result = try await exporter.export(
                assets: assets, groups: imported.manifest.groups, options: options
            )

            XCTAssertEqual(result.exportedCount, pickedCount)

            let exportedFiles = try FileManager.default.subpathsOfDirectory(atPath: exportRoot.path)
            let mediaFiles = exportedFiles.filter { mediaExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }

            for file in mediaFiles {
                let name = URL(fileURLWithPath: file).lastPathComponent
                XCTAssertTrue(name.contains("_"), "datePrefix 命名应含下划线分隔符，实际: \(name)")
            }

            printSummary("EXPORT_BY_DATE", [
                "exported": result.exportedCount,
            ])
        }
    }

    func testExportCustomNaming() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            var assets = imported.manifest.assets
            let pickedCount = min(3, assets.count)
            for i in 0..<pickedCount {
                assets[i].userDecision = .picked
            }

            let exportRoot = ctx.exportRoot.appendingPathComponent("custom", isDirectory: true)
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

            var options = ExportOptions.default
            options.outputPath = exportRoot
            options.folderTemplate = .byGroup
            options.fileNamingRule = .custom
            options.customNamingTemplate = "{date}_{original}"
            options.writeXmpSidecar = false

            let exporter = FolderExporter()
            let result = try await exporter.export(
                assets: assets, groups: imported.manifest.groups, options: options
            )

            XCTAssertEqual(result.exportedCount, pickedCount)

            let exportedFiles = try FileManager.default.subpathsOfDirectory(atPath: exportRoot.path)
            let mediaFiles = exportedFiles.filter { mediaExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            XCTAssertEqual(mediaFiles.count, pickedCount)

            printSummary("EXPORT_CUSTOM", [
                "exported": result.exportedCount,
            ])
        }
    }

    // MARK: - Phase 4: 归档变体

    func testArchiveVideo() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            var assets = imported.manifest.assets
            let pickedCount = min(3, assets.count)
            for i in assets.indices {
                if i < pickedCount {
                    assets[i].userDecision = .picked
                } else {
                    assets[i].userDecision = .pending
                    assets[i].aiScore = TestFixtures.makeAIScore(
                        provider: "e2e", overall: max(55, 80 - i), recommended: false
                    )
                }
            }

            let archiver = VideoArchiver()
            let result = try await archiver.archive(
                groups: imported.manifest.groups,
                assets: assets,
                batchName: "e2e-archive-video"
            )

            XCTAssertFalse(result.generatedFiles.isEmpty, "应至少生成 1 个 MP4")
            XCTAssertTrue(result.generatedFiles.allSatisfy {
                $0.pathExtension.lowercased() == "mp4"
            })
            XCTAssertTrue(result.generatedFiles.allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            })

            let manifestURL = result.outputDirectory.appendingPathComponent("archive_manifest.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

            let data = try Data(contentsOf: manifestURL)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let videos = try XCTUnwrap(json["videos"] as? [[String: Any]])
            XCTAssertEqual(videos.count, result.generatedFiles.count)

            printSummary("ARCHIVE_VIDEO", [
                "mp4_count": result.generatedFiles.count,
                "manifest_ok": true,
            ])
        }
    }

    func testShrinkKeep() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            let candidates = Array(imported.manifest.assets.suffix(10))

            let archiver = VideoArchiver()
            let result = try await archiver.shrinkKeep(
                assets: candidates,
                batchName: "e2e-shrink"
            )

            XCTAssertFalse(result.generatedFiles.isEmpty, "应生成缩图")
            XCTAssertTrue(result.generatedFiles.allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            })

            let manifestURL = result.outputDirectory.appendingPathComponent("archive_manifest.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

            printSummary("SHRINK_KEEP", [
                "shrunk_count": result.generatedFiles.count,
            ])
        }
    }

    func testDiscard() async throws {
        let ctx = try requireSD()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaE2E-discard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await ctx.withAppSupport {
            let imported = try await ctx.importSource()
            let sampled = Array(imported.manifest.assets.prefix(3))
            var copiedAssets: [MediaAsset] = []

            for var asset in sampled {
                if let src = asset.previewURL {
                    let dest = tempDir.appendingPathComponent(src.lastPathComponent)
                    try FileManager.default.copyItem(at: src, to: dest)
                    asset.previewURL = dest
                }
                copiedAssets.append(asset)
            }

            for asset in copiedAssets {
                if let url = asset.previewURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "复制后文件应存在")
                }
            }

            let archiver = VideoArchiver()
            let (deletedCount, _) = await archiver.discard(assets: copiedAssets)

            XCTAssertGreaterThan(deletedCount, 0, "应至少删除 1 个文件")
            for asset in copiedAssets {
                if let url = asset.previewURL {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                                   "discard 后文件应已删除: \(url.lastPathComponent)")
                }
            }

            printSummary("DISCARD", [
                "deleted": deletedCount,
            ])
        }
    }

    // MARK: - Phase 5: 全流程贯通

    func testFullPipelineSDToExportAndArchive() async throws {
        let ctx = try requireSD()
        try await ctx.withAppSupport {
            // 1. Import
            let imported = try await ctx.importSource()
            XCTAssertEqual(imported.manifest.assets.count, ctx.expectedImportCount)

            // 2. Group
            let engine = GroupingEngine()
            let groups = await engine.makeGroups(from: imported.manifest.assets, resolvesLocationNames: false)
            XCTAssertFalse(groups.isEmpty)

            // 3. Local ML scoring (sample)
            let scorer = LocalMLScorer()
            var assets = imported.manifest.assets
            for i in assets.indices.prefix(5) {
                let assessment = await scorer.score(asset: assets[i])
                assets[i].aiScore = AIScore(
                    provider: "local-heuristic",
                    scores: assessment.subscores,
                    overall: assessment.score,
                    comment: assessment.comment,
                    recommended: assessment.recommended,
                    timestamp: .now
                )
                assets[i].issues = assessment.issues
            }

            // 4. Simulated pick: top 30% by score, rest pending
            let sortedIndices = assets.indices.sorted {
                (assets[$0].aiScore?.overall ?? 0) > (assets[$1].aiScore?.overall ?? 0)
            }
            let pickThreshold = max(1, Int(Double(assets.count) * 0.3))
            let pickedIndices = Set(sortedIndices.prefix(pickThreshold))
            for i in assets.indices {
                assets[i].userDecision = pickedIndices.contains(i) ? .picked : .pending
            }

            // 5. Export (byGroup + XMP)
            let exportRoot = ctx.exportRoot.appendingPathComponent("fullPipeline", isDirectory: true)
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

            var exportOptions = ExportOptions.default
            exportOptions.outputPath = exportRoot
            exportOptions.folderTemplate = .byGroup
            exportOptions.writeXmpSidecar = true

            let exporter = FolderExporter()
            let exportResult = try await exporter.export(
                assets: assets, groups: groups, options: exportOptions
            )
            XCTAssertEqual(exportResult.exportedCount, pickedIndices.count)

            // 6. Archive (shrinkKeep for non-picked)
            let archiveCandidates = assets.filter { $0.userDecision != .picked }
            let archiver = VideoArchiver()
            let archiveResult = try await archiver.shrinkKeep(
                assets: archiveCandidates,
                batchName: "e2e-full-pipeline"
            )

            let manifestURL = archiveResult.outputDirectory.appendingPathComponent("archive_manifest.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

            printSummary("FULL_PIPELINE", [
                "imported": imported.manifest.assets.count,
                "groups": groups.count,
                "picked": pickedIndices.count,
                "exported": exportResult.exportedCount,
                "archived": archiveResult.generatedFiles.count,
            ])
        }
    }

    // MARK: - Helpers

    private func printSummary(_ tag: String, _ values: [String: Any]) {
        let pairs = values.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("E2E_REGRESSION[\(tag)] \(pairs)")
    }
}

// MARK: - E2E Context

private struct E2EContext {
    let importURL: URL
    let expectedImportCount: Int
    let runRoot: URL
    let appSupportRoot: URL
    let exportRoot: URL

    static func make(sourceEnvKey: String, prefix: String) throws -> E2EContext {
        guard let rawPath = ProcessInfo.processInfo.environment[sourceEnvKey],
              !rawPath.isEmpty else {
            throw E2ESetupError.missingEnv(sourceEnvKey)
        }

        let importURL = URL(fileURLWithPath: rawPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: importURL.path) else {
            throw E2ESetupError.directoryNotFound(rawPath)
        }

        let outputRootPath = ProcessInfo.processInfo.environment["LUMA_E2E_OUTPUT_ROOT"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("LumaE2EArtifacts").path
        let outputRoot = URL(fileURLWithPath: outputRootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let runID = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let runRoot = outputRoot.appendingPathComponent("\(prefix)-\(runID)", isDirectory: true)
        let appSupportRoot = runRoot.appendingPathComponent("app-support", isDirectory: true)
        let exportRoot = runRoot.appendingPathComponent("exports", isDirectory: true)

        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let discoveredItems = try MediaFileScanner.scan(
            rootFolder: importURL,
            source: .folder(path: importURL.path)
        )

        return E2EContext(
            importURL: importURL,
            expectedImportCount: discoveredItems.count,
            runRoot: runRoot,
            appSupportRoot: appSupportRoot,
            exportRoot: exportRoot
        )
    }

    func importSource() async throws -> ImportedProject {
        try await ImportManager().importFromSource(
            .folder(path: importURL.path, displayName: importURL.lastPathComponent),
            progress: { _ in },
            snapshot: { _ in }
        )
    }

    func withAppSupport<R>(_ body: () async throws -> R) async throws -> R {
        let key = "LUMA_APP_SUPPORT_ROOT"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, appSupportRoot.path, 1)
        defer {
            if let previous { setenv(key, previous, 1) } else { unsetenv(key) }
        }
        return try await body()
    }
}

private enum E2ESetupError: Error, LocalizedError {
    case missingEnv(String)
    case directoryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingEnv(let key): return "环境变量 \(key) 未设置"
        case .directoryNotFound(let path): return "目录不存在: \(path)"
        }
    }
}

private let mediaExtensions: Set<String> = [
    "jpg", "jpeg", "heic", "heif", "png",
    "arw", "cr3", "nef", "raf", "dng", "orf", "rw2"
]
