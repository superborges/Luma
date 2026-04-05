import CoreGraphics
import Foundation
import XCTest
@testable import Luma

final class EndToEndSmokeTests: XCTestCase {
    func testImportExportAndArchiveVideoSmokePath() async throws {
        let importManager = ImportManager()
        let exporter = FolderExporter()
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory(prefix: "LumaSmoke") { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("SmokeSource", isDirectory: true)
                let exportRoot = root.appendingPathComponent("SmokeExport", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

                let firstURL = sourceRoot.appendingPathComponent("IMG_7001.JPG")
                let secondURL = sourceRoot.appendingPathComponent("IMG_7002.JPG")
                try TestFixtures.makeJPEG(at: firstURL)
                try TestFixtures.makeJPEG(at: secondURL)

                let firstItem = DiscoveredItem(
                    id: UUID(),
                    resumeKey: "img_7001",
                    baseName: "IMG_7001",
                    source: .folder(path: sourceRoot.path),
                    previewFile: firstURL,
                    rawFile: nil,
                    auxiliaryFile: nil,
                    depthData: false,
                    metadata: EXIFData(
                        captureDate: TestFixtures.makeDate(hour: 18),
                        gpsCoordinate: Coordinate(latitude: 31.2304, longitude: 121.4737),
                        focalLength: 35,
                        aperture: 2.0,
                        shutterSpeed: "1/125",
                        iso: 100,
                        cameraModel: "Smoke Cam",
                        lensModel: "Smoke Lens",
                        imageWidth: 3000,
                        imageHeight: 2000
                    ),
                    mediaType: .photo
                )
                let secondItem = DiscoveredItem(
                    id: UUID(),
                    resumeKey: "img_7002",
                    baseName: "IMG_7002",
                    source: .folder(path: sourceRoot.path),
                    previewFile: secondURL,
                    rawFile: nil,
                    auxiliaryFile: nil,
                    depthData: false,
                    metadata: EXIFData(
                        captureDate: TestFixtures.makeDate(hour: 18, minute: 1),
                        gpsCoordinate: Coordinate(latitude: 31.2305, longitude: 121.4738),
                        focalLength: 50,
                        aperture: 2.8,
                        shutterSpeed: "1/60",
                        iso: 200,
                        cameraModel: "Smoke Cam",
                        lensModel: "Smoke Lens",
                        imageWidth: 3000,
                        imageHeight: 2000
                    ),
                    mediaType: .photo
                )

                let imported = try await importManager.importFromSource(
                    .folder(path: sourceRoot.path, displayName: "SmokeSource"),
                    adapter: SmokeImportAdapter(items: [firstItem, secondItem]),
                    progress: { _ in },
                    snapshot: { _ in }
                )

                XCTAssertEqual(imported.manifest.assets.count, 2)
                XCTAssertEqual(imported.manifest.groups.count, 1)

                var assets = imported.manifest.assets
                let group = try XCTUnwrap(imported.manifest.groups.first)
                guard let firstIndex = assets.firstIndex(where: { $0.importResumeKey == "img_7001" }),
                      let secondIndex = assets.firstIndex(where: { $0.importResumeKey == "img_7002" }) else {
                    XCTFail("Expected imported assets to keep resume keys")
                    return
                }

                assets[firstIndex].userDecision = .picked
                assets[firstIndex].aiScore = TestFixtures.makeAIScore(provider: "smoke-local", overall: 95, recommended: true, comment: "Hero frame")
                assets[secondIndex].userDecision = .pending
                assets[secondIndex].aiScore = TestFixtures.makeAIScore(provider: "smoke-local", overall: 61, recommended: false, comment: "Archive frame")

                var exportOptions = ExportOptions.default
                exportOptions.outputPath = exportRoot
                exportOptions.folderTemplate = .byGroup
                exportOptions.writeXmpSidecar = true
                exportOptions.rejectedHandling = .discard

                let exportResult = try await exporter.export(assets: assets, groups: [group], options: exportOptions)

                let exportFolder = exportRoot.appendingPathComponent(AppDirectories.sanitizePathComponent(group.name), isDirectory: true)
                let exportedImage = exportFolder.appendingPathComponent("IMG_7001_\(assets[firstIndex].id.uuidString.prefix(8)).JPG")
                let exportedXMP = exportFolder.appendingPathComponent("IMG_7001_\(assets[firstIndex].id.uuidString.prefix(8)).xmp")

                XCTAssertEqual(exportResult.exportedCount, 1)
                XCTAssertTrue(FileManager.default.fileExists(atPath: exportedImage.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: exportedXMP.path))

                let archiveResult = try await archiver.archive(groups: [group], assets: assets, batchName: "Smoke Archive")
                let archiveManifestURL = archiveResult.outputDirectory.appendingPathComponent("archive_manifest.json")
                let archiveVideoURL = try XCTUnwrap(archiveResult.generatedFiles.first)

                XCTAssertEqual(archiveResult.generatedFiles.count, 1)
                XCTAssertTrue(FileManager.default.fileExists(atPath: archiveVideoURL.path))
                XCTAssertEqual(archiveVideoURL.pathExtension.lowercased(), "mp4")
                XCTAssertTrue(FileManager.default.fileExists(atPath: archiveManifestURL.path))

                let manifestData = try Data(contentsOf: archiveManifestURL)
                let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
                let videos = try XCTUnwrap(manifestObject["videos"] as? [[String: Any]])
                let firstVideo = try XCTUnwrap(videos.first)
                let items = try XCTUnwrap(firstVideo["items"] as? [[String: Any]])

                XCTAssertEqual(manifestObject["batchName"] as? String, "Smoke Archive")
                XCTAssertEqual(videos.count, 1)
                XCTAssertEqual(firstVideo["groupName"] as? String, group.name)
                XCTAssertEqual(firstVideo["photoCount"] as? Int, 1)
                XCTAssertEqual(items.first?["originalFileName"] as? String, assets[secondIndex].previewURL?.lastPathComponent)
            }
        }
    }
}

private final class SmokeImportAdapter: ImportSourceAdapter, @unchecked Sendable {
    let displayName: String
    let items: [DiscoveredItem]

    init(displayName: String = "Smoke Import Source", items: [DiscoveredItem]) {
        self.displayName = displayName
        self.items = items
    }

    func enumerate() async throws -> [DiscoveredItem] {
        items
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        guard let sourceURL = item.previewFile else { return nil }
        return EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 400)
    }

    func copyPreview(_ item: DiscoveredItem, to destination: URL) async throws {
        try Self.copy(from: item.previewFile, to: destination)
    }

    func copyOriginal(_ item: DiscoveredItem, to destination: URL) async throws {
        try Self.copy(from: item.rawFile, to: destination)
    }

    func copyAuxiliary(_ item: DiscoveredItem, to destination: URL) async throws {
        try Self.copy(from: item.auxiliaryFile, to: destination)
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.finish()
        }
    }

    private static func copy(from sourceURL: URL?, to destination: URL) throws {
        guard let sourceURL else { return }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }
}
