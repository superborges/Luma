import XCTest
@testable import Luma

final class FolderExporterTests: XCTestCase {
    func testValidateConfigurationRequiresOutputPath() async throws {
        let exporter = FolderExporter()
        var options = ExportOptions.default
        options.outputPath = nil

        let isValid = try await exporter.validateConfiguration(options: options)

        XCTAssertFalse(isValid)
    }

    func testExportCopiesPickedAssetsIntoGroupFolderAndWritesXMP() async throws {
        let exporter = FolderExporter()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            let outputRoot = root.appendingPathComponent("Output", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

            let pickedSource = sourceRoot.appendingPathComponent("IMG_8001.JPG")
            let pendingSource = sourceRoot.appendingPathComponent("IMG_8002.JPG")
            try TestFixtures.createFile(at: pickedSource, modifiedAt: TestFixtures.makeDate(hour: 16))
            try TestFixtures.createFile(at: pendingSource, modifiedAt: TestFixtures.makeDate(hour: 16, minute: 1))

            let pickedAsset = TestFixtures.makeAsset(
                baseName: "IMG_8001",
                captureDate: TestFixtures.makeDate(hour: 16),
                aiScore: TestFixtures.makeAIScore(overall: 92, recommended: true, comment: "Best frame"),
                userDecision: .picked
            )
            var picked = pickedAsset
            picked.previewURL = pickedSource

            var pending = TestFixtures.makeAsset(
                baseName: "IMG_8002",
                captureDate: TestFixtures.makeDate(hour: 16, minute: 1),
                aiScore: TestFixtures.makeAIScore(overall: 70),
                userDecision: .pending
            )
            pending.previewURL = pendingSource

            let group = TestFixtures.makeGroup(
                name: "Bund / Night: Selects",
                assets: [picked, pending],
                recommendedAssets: [picked.id]
            )

            var options = ExportOptions.default
            options.outputPath = outputRoot
            options.folderTemplate = .byGroup
            options.writeXmpSidecar = true
            options.writeEditSuggestionsToXmp = false

            let result = try await exporter.export(assets: [picked, pending], groups: [group], options: options)

            let expectedFolder = outputRoot.appendingPathComponent("Bund - Night- Selects", isDirectory: true)
            let exportedImage = expectedFolder.appendingPathComponent("IMG_8001.JPG")
            let exportedXMP = expectedFolder.appendingPathComponent("IMG_8001.xmp")

            XCTAssertEqual(result.exportedCount, 1)
            XCTAssertEqual(result.skippedCount, 0)
            XCTAssertEqual(result.destinationDescription, outputRoot.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: exportedImage.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: exportedXMP.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("IMG_8002.JPG").path))

            let xmp = try String(contentsOf: exportedXMP, encoding: .utf8)
            XCTAssertTrue(xmp.contains("Best frame"))
        }
    }
}
