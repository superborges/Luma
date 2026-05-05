import Foundation
import XCTest
@testable import Luma

final class VideoArchiverTests: XCTestCase {

    // MARK: - ShrinkKeep

    func testShrinkKeepGeneratesJPEGsToOutputDirectory() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
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

            let outputDir = root.appendingPathComponent("shrunk_output", isDirectory: true)
            let result = try await archiver.shrinkKeep(
                assets: [renderable, skipped],
                outputDirectory: outputDir
            )

            XCTAssertEqual(result.photoCount, 1)
            XCTAssertEqual(result.skippedCount, 1)
            XCTAssertEqual(result.outputURL, outputDir)

            let outputJPEG = outputDir.appendingPathComponent("Select- 1.jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputJPEG.path))
        }
    }

    func testShrinkKeepDeletesRAWAfterSuccess() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
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

            let outputDir = root.appendingPathComponent("shrunk_raw", isDirectory: true)
            let result = try await archiver.shrinkKeep(assets: [asset], outputDirectory: outputDir)

            XCTAssertEqual(result.photoCount, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: rawURL.path))
            XCTAssertTrue(result.freedBytes > 0)
        }
    }

    func testShrinkKeepReportsProgressCallback() async throws {
        let archiver = VideoArchiver()
        let collector = ProgressCollector()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

            let url = sourceRoot.appendingPathComponent("IMG_2001.JPG")
            try TestFixtures.makeJPEG(at: url)

            var asset = TestFixtures.makeAsset(baseName: "Progress1", captureDate: TestFixtures.makeDate(hour: 8))
            asset.previewURL = url

            let outputDir = root.appendingPathComponent("shrunk_progress", isDirectory: true)
            _ = try await archiver.shrinkKeep(assets: [asset], outputDirectory: outputDir) { progress in
                collector.append(progress)
            }

            let updates = collector.values
            XCTAssertFalse(updates.isEmpty)
            XCTAssertEqual(updates.first?.completed, 0)
            XCTAssertEqual(updates.first?.total, 1)
            XCTAssertEqual(updates.first?.currentName, "Progress1")
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

    // MARK: - Archive Video

    func testArchiveVideoMergesAllAssetsIntoSingleFile() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

            let img1 = sourceRoot.appendingPathComponent("IMG_0001.JPG")
            let img2 = sourceRoot.appendingPathComponent("IMG_0002.JPG")
            try TestFixtures.makeJPEG(at: img1)
            try TestFixtures.makeJPEG(at: img2)

            var a1 = TestFixtures.makeAsset(baseName: "A1", captureDate: TestFixtures.makeDate(hour: 10), userDecision: .rejected)
            a1.previewURL = img1
            var a2 = TestFixtures.makeAsset(baseName: "A2", captureDate: TestFixtures.makeDate(hour: 11), userDecision: .rejected)
            a2.previewURL = img2
            let noImage = TestFixtures.makeAsset(baseName: "NoSrc", captureDate: TestFixtures.makeDate(hour: 12), userDecision: .rejected)

            let outputURL = root.appendingPathComponent("archive.mp4")
            let result = try await archiver.archive(
                assets: [a1, a2, noImage],
                title: "Test Project",
                outputURL: outputURL
            )

            let mp4 = try XCTUnwrap(result.outputURL)
            XCTAssertEqual(mp4, outputURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: mp4.path))
            XCTAssertEqual(result.photoCount, 2)
            XCTAssertEqual(result.skippedCount, 1)
        }
    }

    func testArchiveVideoUsesOnDiskThumbnailWhenPreviewFileMissing() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
            let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

            let thumbURL = sourceRoot.appendingPathComponent("thumb_only.jpg")
            try TestFixtures.makeJPEG(at: thumbURL)
            let missingPreview = sourceRoot.appendingPathComponent("missing_preview.jpg")

            var asset = TestFixtures.makeAsset(baseName: "ThumbFallback", captureDate: TestFixtures.makeDate(hour: 10), userDecision: .rejected)
            asset.previewURL = missingPreview
            asset.thumbnailURL = thumbURL

            XCTAssertFalse(FileManager.default.fileExists(atPath: missingPreview.path))
            XCTAssertEqual(asset.existingImageFileURL, thumbURL)

            let outputURL = root.appendingPathComponent("fallback.mp4")
            let result = try await archiver.archive(
                assets: [asset],
                title: "Fallback",
                outputURL: outputURL
            )

            XCTAssertNotNil(result.outputURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            XCTAssertEqual(result.photoCount, 1)
            XCTAssertEqual(result.skippedCount, 0)
        }
    }

    func testArchiveVideoReturnsNilWhenNoRenderableAssets() async throws {
        let archiver = VideoArchiver()

        try await TestFixtures.withTemporaryDirectory { root in
            let asset = TestFixtures.makeAsset(baseName: "NoSrc", captureDate: TestFixtures.makeDate(hour: 10), userDecision: .rejected)
            let outputURL = root.appendingPathComponent("empty.mp4")
            let result = try await archiver.archive(assets: [asset], title: "Empty", outputURL: outputURL)

            XCTAssertNil(result.outputURL)
            XCTAssertEqual(result.photoCount, 0)
            XCTAssertEqual(result.skippedCount, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
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
