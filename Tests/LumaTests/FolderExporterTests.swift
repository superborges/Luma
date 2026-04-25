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

    /// 与 `groupLookup` 的 `uniquingKeysWith: { first, _ in first }` 对齐：同一张图出现在多组时，以 `groups` 数组**最先**出现的那组名作为目录。
    func testExportUsesFirstGroupWhenAssetAppearsInMultipleGroups() async throws {
        let exporter = FolderExporter()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            let outputRoot = root.appendingPathComponent("Output", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

            let fileURL = sourceRoot.appendingPathComponent("SHARED.JPG")
            let capture = TestFixtures.makeDate(hour: 10)
            try TestFixtures.createFile(at: fileURL, modifiedAt: capture)

            let sharedID = UUID()
            var asset = TestFixtures.makeAsset(
                id: sharedID,
                baseName: "SHARED",
                captureDate: capture,
                userDecision: .picked
            )
            asset.previewURL = fileURL

            let groupAlpha = TestFixtures.makeGroup(name: "Alpha Scene", assets: [asset], recommendedAssets: [sharedID])
            let groupBeta = TestFixtures.makeGroup(name: "Beta Scene", assets: [asset], recommendedAssets: [sharedID])

            var options = ExportOptions.default
            options.outputPath = outputRoot
            options.folderTemplate = .byGroup
            options.writeXmpSidecar = false

            let result = try await exporter.export(
                assets: [asset],
                groups: [groupAlpha, groupBeta],
                options: options
            )

            XCTAssertEqual(result.exportedCount, 1, "应只导出一份文件，不重复到两个组目录")
            XCTAssertTrue(result.failures.isEmpty, "\(result.failures)")

            let alphaFolder = outputRoot.appendingPathComponent("Alpha Scene", isDirectory: true)
            let betaFolder = outputRoot.appendingPathComponent("Beta Scene", isDirectory: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: alphaFolder.appendingPathComponent("SHARED.JPG").path))
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: betaFolder.appendingPathComponent("SHARED.JPG").path),
                "后出现的组不应再得到同一资产的副本"
            )
        }
    }

    func testExportUsesFirstGroupInArrayWhenDuplicateAssetOrderReversed() async throws {
        let exporter = FolderExporter()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            let outputRoot = root.appendingPathComponent("Output", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

            let fileURL = sourceRoot.appendingPathComponent("REV.JPG")
            let capture = TestFixtures.makeDate(hour: 11)
            try TestFixtures.createFile(at: fileURL, modifiedAt: capture)

            let sharedID = UUID()
            var asset = TestFixtures.makeAsset(
                id: sharedID,
                baseName: "REV",
                captureDate: capture,
                userDecision: .picked
            )
            asset.previewURL = fileURL

            let groupAlpha = TestFixtures.makeGroup(name: "Alpha Scene", assets: [asset], recommendedAssets: [sharedID])
            let groupBeta = TestFixtures.makeGroup(name: "Beta Scene", assets: [asset], recommendedAssets: [sharedID])

            var options = ExportOptions.default
            options.outputPath = outputRoot
            options.folderTemplate = .byGroup
            options.writeXmpSidecar = false

            _ = try await exporter.export(assets: [asset], groups: [groupBeta, groupAlpha], options: options)

            let alphaFolder = outputRoot.appendingPathComponent("Alpha Scene", isDirectory: true)
            let betaFolder = outputRoot.appendingPathComponent("Beta Scene", isDirectory: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: betaFolder.appendingPathComponent("REV.JPG").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: alphaFolder.appendingPathComponent("REV.JPG").path))
        }
    }
}
