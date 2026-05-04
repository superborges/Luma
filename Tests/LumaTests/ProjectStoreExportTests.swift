import Foundation
import XCTest
@testable import Luma

@MainActor
final class ProjectStoreExportTests: XCTestCase {
    func testPerformExportRejectsEmptyProject() async {
        let store = ProjectStore(enableImportMonitoring: false)

        await store.performExport()

        XCTAssertEqual(store.lastErrorMessage, "当前没有可导出的项目。")
        XCTAssertFalse(store.isExporting)
    }

    func testPerformExportRejectsWhenNothingIsPicked() async {
        let store = ProjectStore(enableImportMonitoring: false)
        TestFixtures.seedStore(
            store,
            assets: [
                TestFixtures.makeAsset(baseName: "IMG_5001", captureDate: TestFixtures.makeDate(hour: 13), aiScore: TestFixtures.makeAIScore(overall: 80))
            ]
        )

        await store.performExport()

        XCTAssertEqual(store.lastErrorMessage, "请先至少标记一张 Picked 照片。")
        XCTAssertFalse(store.isExporting)
    }

    func testPerformExportWritesFolderExportSummaryAndClosesPanel() async throws {
        try await TestFixtures.withTemporaryDirectory { root in
            let store = ProjectStore(enableImportMonitoring: false)
            let sourceRoot = root.appendingPathComponent("ExportSource", isDirectory: true)
            let outputRoot = root.appendingPathComponent("ExportOutput", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

            let pickedURL = sourceRoot.appendingPathComponent("IMG_5002.JPG")
            let pendingURL = sourceRoot.appendingPathComponent("IMG_5003.JPG")
            try TestFixtures.createFile(at: pickedURL, modifiedAt: TestFixtures.makeDate(hour: 14))
            try TestFixtures.createFile(at: pendingURL, modifiedAt: TestFixtures.makeDate(hour: 14, minute: 1))

            var picked = TestFixtures.makeAsset(
                baseName: "IMG_5002",
                captureDate: TestFixtures.makeDate(hour: 14),
                aiScore: TestFixtures.makeAIScore(overall: 95, recommended: true, comment: "Keep this"),
                userDecision: .picked
            )
            picked.previewURL = pickedURL

            var pending = TestFixtures.makeAsset(
                baseName: "IMG_5003",
                captureDate: TestFixtures.makeDate(hour: 14, minute: 1),
                aiScore: TestFixtures.makeAIScore(overall: 60),
                userDecision: .pending
            )
            pending.previewURL = pendingURL

            let group = TestFixtures.makeGroup(
                name: "Export Group",
                assets: [picked, pending],
                recommendedAssets: [picked.id]
            )

            TestFixtures.seedStore(store, name: "Export Project", assets: [picked, pending], groups: [group])
            store.isExportPanelPresented = true
            store.exportOptions.destination = .folder
            store.exportOptions.outputPath = outputRoot
            store.exportOptions.folderTemplate = .byGroup
            store.exportOptions.writeXmpSidecar = true
            store.exportOptions.rejectedHandling = .discard

            Task { @MainActor in
                while !store.isAwaitingDiscardConfirmation {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                store.resolveDiscardConfirmation(true)
            }

            await store.performExport()

            let exportedFolder = outputRoot.appendingPathComponent("Export Group", isDirectory: true)
            XCTAssertNil(store.lastErrorMessage)
            XCTAssertFalse(store.isExporting)
            XCTAssertFalse(store.isExportPanelPresented)
            XCTAssertTrue(store.lastExportSummary?.contains("导出 1 张到") == true)
            XCTAssertEqual(store.lastSummaryStatus, store.lastExportSummary)
            XCTAssertTrue(FileManager.default.fileExists(atPath: exportedFolder.appendingPathComponent("IMG_5002.JPG").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: exportedFolder.appendingPathComponent("IMG_5002.xmp").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: exportedFolder.appendingPathComponent("IMG_5003.JPG").path))
        }
    }

    func testPerformExportSurfacesInvalidConfiguration() async throws {
        try await TestFixtures.withTemporaryDirectory { root in
            let store = ProjectStore(enableImportMonitoring: false)
            let sourceURL = root.appendingPathComponent("IMG_5004.JPG")
            try TestFixtures.createFile(at: sourceURL, modifiedAt: TestFixtures.makeDate(hour: 15))

            var picked = TestFixtures.makeAsset(
                baseName: "IMG_5004",
                captureDate: TestFixtures.makeDate(hour: 15),
                aiScore: TestFixtures.makeAIScore(overall: 90, recommended: true),
                userDecision: .picked
            )
            picked.previewURL = sourceURL

            let g = TestFixtures.makeGroup(name: "Needs Folder", assets: [picked])
            TestFixtures.seedStore(store, assets: [picked], groups: [g])
            store.exportOptions.destination = .folder
            store.exportOptions.outputPath = nil

            await store.performExport()

            XCTAssertEqual(store.lastErrorMessage, "导出配置不完整。")
            XCTAssertFalse(store.isExporting)
        }
    }
}
