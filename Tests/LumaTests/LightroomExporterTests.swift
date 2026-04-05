import XCTest
@testable import Luma

final class LightroomExporterTests: XCTestCase {
    func testValidateConfigurationRequiresAutoImportFolder() async throws {
        let exporter = LightroomExporter()
        var options = ExportOptions.default
        options.lrAutoImportFolder = nil

        let isValid = try await exporter.validateConfiguration(options: options)

        XCTAssertFalse(isValid)
    }

    func testExportUsesLightroomFolderAndAlwaysWritesXMP() async throws {
        let exporter = LightroomExporter()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            let ignoredOutputRoot = root.appendingPathComponent("IgnoredOutput", isDirectory: true)
            let autoImportRoot = root.appendingPathComponent("LightroomAutoImport", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ignoredOutputRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: autoImportRoot, withIntermediateDirectories: true)

            let sourceURL = sourceRoot.appendingPathComponent("IMG_8101.JPG")
            try TestFixtures.createFile(at: sourceURL, modifiedAt: TestFixtures.makeDate(hour: 17))

            var picked = TestFixtures.makeAsset(
                baseName: "IMG_8101",
                captureDate: TestFixtures.makeDate(hour: 17),
                aiScore: TestFixtures.makeAIScore(overall: 90, recommended: true, comment: "LR target"),
                userDecision: .picked
            )
            picked.previewURL = sourceURL

            let group = TestFixtures.makeGroup(
                name: "Catalog Import",
                assets: [picked],
                recommendedAssets: [picked.id]
            )

            var options = ExportOptions.default
            options.outputPath = ignoredOutputRoot
            options.lrAutoImportFolder = autoImportRoot
            options.folderTemplate = .byDate
            options.writeXmpSidecar = false

            let result = try await exporter.export(assets: [picked], groups: [group], options: options)

            let expectedFolder = autoImportRoot.appendingPathComponent("2026-04-04", isDirectory: true)
            XCTAssertEqual(result.exportedCount, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("IMG_8101.JPG").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("IMG_8101.xmp").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: ignoredOutputRoot.appendingPathComponent("2026-04-04/IMG_8101.JPG").path))
        }
    }
}
