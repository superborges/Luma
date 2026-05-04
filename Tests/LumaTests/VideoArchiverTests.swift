import Foundation
import XCTest
@testable import Luma

final class VideoArchiverTests: XCTestCase {

    // MARK: - ShrinkKeep

    func testShrinkKeepGeneratesJPEGsAndManifestForRenderableAssets() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let imageURL = sourceRoot.appendingPathComponent("IMG_9001.JPG")
                try TestFixtures.makeJPEG(at: imageURL)

                var renderable = TestFixtures.makeAsset(
                    baseName: "Select: 1",
                    captureDate: TestFixtures.makeDate(hour: 19),
                    aiScore: TestFixtures.makeAIScore(overall: 94, recommended: true)
                )
                renderable.previewURL = imageURL

                let skipped = TestFixtures.makeAsset(
                    baseName: "Missing Source",
                    captureDate: TestFixtures.makeDate(hour: 19, minute: 1)
                )

                let result = try await archiver.shrinkKeep(
                    assets: [renderable, skipped],
                    batchName: "Batch: Spring / Test"
                )

                let outputJPEG = try XCTUnwrap(result.generatedFiles.first)
                let manifestURL = result.outputDirectory.appendingPathComponent("archive_manifest.json")

                XCTAssertEqual(result.generatedFiles.count, 1)
                XCTAssertEqual(result.skippedCount, 1)
                XCTAssertTrue(result.outputDirectory.lastPathComponent == "Batch- Spring - Test")
                XCTAssertEqual(outputJPEG.lastPathComponent, "Select- 1.jpg")
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputJPEG.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

                let manifestData = try Data(contentsOf: manifestURL)
                let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
                let entries = try XCTUnwrap(manifestObject["entries"] as? [[String: Any]])

                XCTAssertEqual(manifestObject["batchName"] as? String, "Batch: Spring / Test")
                XCTAssertEqual((manifestObject["videos"] as? [Any])?.count, 0)
                XCTAssertEqual(entries.count, 1)
                XCTAssertEqual(entries.first?["originalFileName"] as? String, "IMG_9001.JPG")
                XCTAssertEqual(entries.first?["outputFileName"] as? String, "Select- 1.jpg")
                XCTAssertEqual(entries.first?["aiScore"] as? Int, 94)
                XCTAssertEqual(entries.first?["archiveMethod"] as? String, "shrinkKeep")
            }
        }
    }

    func testShrinkKeepDeletesRAWAfterSuccess() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let previewURL = sourceRoot.appendingPathComponent("IMG_1001.JPG")
                try TestFixtures.makeJPEG(at: previewURL)
                let rawURL = sourceRoot.appendingPathComponent("IMG_1001.CR3")
                FileManager.default.createFile(atPath: rawURL.path, contents: Data(repeating: 0xFF, count: 4096))

                var asset = TestFixtures.makeAsset(
                    baseName: "RAW_Test",
                    captureDate: TestFixtures.makeDate(hour: 10)
                )
                asset.previewURL = previewURL
                asset.rawURL = rawURL

                XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))

                let result = try await archiver.shrinkKeep(assets: [asset], batchName: "RAWDelete")

                XCTAssertEqual(result.generatedFiles.count, 1)
                XCTAssertFalse(FileManager.default.fileExists(atPath: rawURL.path))
                XCTAssertTrue(result.freedBytes > 0)
            }
        }
    }

    func testShrinkKeepReportsProgressCallback() async throws {
        let archiver = VideoArchiver()
        let collector = ProgressCollector()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let url = sourceRoot.appendingPathComponent("IMG_2001.JPG")
                try TestFixtures.makeJPEG(at: url)

                var asset = TestFixtures.makeAsset(baseName: "Progress1", captureDate: TestFixtures.makeDate(hour: 8))
                asset.previewURL = url

                _ = try await archiver.shrinkKeep(assets: [asset], batchName: "ProgressTest") { progress in
                    collector.append(progress)
                }

                let updates = collector.values
                XCTAssertFalse(updates.isEmpty)
                XCTAssertEqual(updates.first?.completed, 0)
                XCTAssertEqual(updates.first?.total, 1)
                XCTAssertEqual(updates.first?.currentName, "Progress1")
            }
        }
    }

    // MARK: - Discard

    func testDiscardDeletesFiles() async throws {
        let archiver = VideoArchiver()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let previewURL = root.appendingPathComponent("IMG_3001.JPG")
        let rawURL = root.appendingPathComponent("IMG_3001.CR3")
        FileManager.default.createFile(atPath: previewURL.path, contents: Data(repeating: 0xAA, count: 1024))
        FileManager.default.createFile(atPath: rawURL.path, contents: Data(repeating: 0xBB, count: 2048))

        var asset = TestFixtures.makeAsset(baseName: "Discard1", captureDate: TestFixtures.makeDate(hour: 14))
        asset.previewURL = previewURL
        asset.rawURL = rawURL

        let result = await archiver.discard(assets: [asset])

        XCTAssertEqual(result.deletedCount, 2)
        XCTAssertEqual(result.freedBytes, 3072)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rawURL.path))
    }

    func testDiscardSkipsMissingFiles() async {
        let archiver = VideoArchiver()
        let asset = TestFixtures.makeAsset(baseName: "NoFile", captureDate: TestFixtures.makeDate(hour: 15))
        let result = await archiver.discard(assets: [asset])
        XCTAssertEqual(result.deletedCount, 0)
        XCTAssertEqual(result.freedBytes, 0)
    }

    // MARK: - Manifest Serialization

    func testArchiveManifestRoundTrip() throws {
        let entry = ArchiveManifestEntry(
            originalFileName: "IMG_0001.JPG",
            outputFileName: "Photo1.jpg",
            captureDate: TestFixtures.makeDate(hour: 12),
            aiScore: 85,
            archiveMethod: "shrinkKeep"
        )
        let videoItem = ArchiveVideoItem(
            originalFileName: "IMG_0002.JPG",
            captureDate: TestFixtures.makeDate(hour: 13),
            aiScore: 72,
            startTime: 1.0,
            endTime: 2.5
        )
        let video = ArchiveVideoEntry(
            fileName: "01_Morning_archive.mp4",
            groupName: "Morning",
            photoCount: 1,
            duration: 2.5,
            fileSize: 500_000,
            items: [videoItem]
        )
        let manifest = ArchiveManifest(batchName: "TestBatch", videos: [video], entries: [entry])

        let data = try JSONEncoder.lumaEncoder.encode(manifest)
        let decoded = try JSONDecoder.lumaDecoder.decode(ArchiveManifest.self, from: data)

        XCTAssertEqual(decoded.batchName, "TestBatch")
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries.first?.originalFileName, "IMG_0001.JPG")
        XCTAssertEqual(decoded.entries.first?.aiScore, 85)
        XCTAssertEqual(decoded.videos.count, 1)
        XCTAssertEqual(decoded.videos.first?.groupName, "Morning")
        XCTAssertEqual(decoded.videos.first?.items.count, 1)
    }

    // MARK: - Disk Space Estimation

    func testEstimateArchiveSizeForShrinkKeep() {
        let assets = (0..<10).map {
            TestFixtures.makeAsset(baseName: "E\($0)", captureDate: TestFixtures.makeDate(hour: 8))
        }
        let size = VideoArchiver.estimateArchiveSize(assets: assets, handling: .shrinkKeep)
        XCTAssertEqual(size, 8_000_000)
    }

    func testEstimateArchiveSizeForDiscard() {
        let assets = [TestFixtures.makeAsset(baseName: "D1", captureDate: TestFixtures.makeDate(hour: 8))]
        let size = VideoArchiver.estimateArchiveSize(assets: assets, handling: .discard)
        XCTAssertEqual(size, 0)
    }
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [ArchiveProgress] = []

    func append(_ progress: ArchiveProgress) {
        lock.lock()
        _values.append(progress)
        lock.unlock()
    }

    var values: [ArchiveProgress] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
}
