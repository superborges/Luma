import XCTest
@testable import Luma

@MainActor
final class ThumbnailCacheTests: XCTestCase {
    func testImageGeneratesThumbnailWhenDiskCacheIsMissing() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "ThumbnailCache") { root in
            let cache = ThumbnailCache(countLimit: 8)

            let previewURL = root.appendingPathComponent("IMG_0001.JPG")
            let thumbnailURL = root.appendingPathComponent("thumbs/IMG_0001.png")
            try TestFixtures.makeJPEG(at: previewURL, size: CGSize(width: 120, height: 80))

            var asset = TestFixtures.makeAsset(
                baseName: "IMG_0001",
                captureDate: TestFixtures.makeDate(hour: 10)
            )
            asset.previewURL = previewURL
            asset.thumbnailURL = thumbnailURL

            cache.invalidateAll()
            cache.resetDiagnostics()

            let image = await cache.image(for: asset)

            XCTAssertNotNil(image)
            XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

            let snapshot = cache.snapshot()
            XCTAssertEqual(snapshot.generatedImages, 1)
            XCTAssertEqual(snapshot.diskHits, 0)
        }
    }

    func testImageLoadsExistingThumbnailFromDiskAfterMemoryInvalidation() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "ThumbnailCache") { root in
            let cache = ThumbnailCache(countLimit: 8)

            let previewURL = root.appendingPathComponent("IMG_0002.JPG")
            let thumbnailURL = root.appendingPathComponent("thumbs/IMG_0002.png")
            try TestFixtures.makeJPEG(at: previewURL, size: CGSize(width: 120, height: 80))

            var asset = TestFixtures.makeAsset(
                baseName: "IMG_0002",
                captureDate: TestFixtures.makeDate(hour: 11)
            )
            asset.previewURL = previewURL
            asset.thumbnailURL = thumbnailURL

            cache.invalidateAll()
            cache.resetDiagnostics()

            let generatedImage = await cache.image(for: asset)
            XCTAssertNotNil(generatedImage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

            cache.invalidateAll()
            cache.resetDiagnostics()

            let diskLoadedImage = await cache.image(for: asset)

            XCTAssertNotNil(diskLoadedImage)

            let snapshot = cache.snapshot()
            XCTAssertEqual(snapshot.diskHits, 1)
            XCTAssertEqual(snapshot.generatedImages, 0)
        }
    }
}
