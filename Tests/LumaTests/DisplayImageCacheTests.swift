import XCTest
@testable import Luma

@MainActor
final class DisplayImageCacheTests: XCTestCase {
    private let cache = DisplayImageCache.shared

    func testImageDecodesAndCachesFromPreviewURL() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "DisplayImageCache") { root in
            cache.invalidateAll()
            cache.resetDiagnostics()
            defer { cache.invalidateAll() }

            let previewURL = root.appendingPathComponent("display.jpg")
            try TestFixtures.makeJPEG(at: previewURL, size: CGSize(width: 120, height: 80))

            var asset = TestFixtures.makeAsset(
                baseName: "IMG_DISPLAY",
                captureDate: TestFixtures.makeDate(hour: 9)
            )
            asset.previewURL = previewURL

            let first = await cache.image(for: asset)
            XCTAssertNotNil(first)

            let memory = cache.cachedImage(for: asset)
            XCTAssertNotNil(memory)

            let hitAgain = await cache.image(for: asset)
            XCTAssertNotNil(hitAgain)

            let snap = cache.snapshot()
            XCTAssertGreaterThanOrEqual(snap.decodedImages, 1)
            XCTAssertGreaterThanOrEqual(snap.memoryHits, 1)
        }
    }

    func testPreheatNeighborhoodSkipsWhenSignatureUnchanged() async throws {
        try TestFixtures.withTemporaryDirectory(prefix: "DisplayImageCache") { root in
            cache.invalidateAll()
            cache.resetDiagnostics()
            defer { cache.invalidateAll() }

            let ids = (0..<3).map { _ in UUID() }
            var assets: [MediaAsset] = []
            for (idx, id) in ids.enumerated() {
                let url = root.appendingPathComponent("n\(idx).jpg")
                try TestFixtures.makeJPEG(at: url, size: CGSize(width: 32, height: 24))
                var a = TestFixtures.makeAsset(
                    id: id,
                    baseName: "N\(idx)",
                    captureDate: TestFixtures.makeDate(hour: 10)
                )
                a.previewURL = url
                assets.append(a)
            }

            let centerID = assets[1].id
            cache.preheatNeighborhood(around: centerID, in: assets, radius: 1)
            let afterFirst = cache.snapshot().preheatedItems

            cache.preheatNeighborhood(around: centerID, in: assets, radius: 1)
            let afterSecond = cache.snapshot().preheatedItems
            XCTAssertEqual(afterFirst, afterSecond, "同签名第二次应跳过预热")
        }
    }

    func testPreheatNeighborhoodTrimsToNeighborhood() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "DisplayImageCache") { root in
            cache.invalidateAll()
            cache.resetDiagnostics()
            defer { cache.invalidateAll() }

            var assets: [MediaAsset] = []
            for idx in 0..<3 {
                let id = UUID()
                let url = root.appendingPathComponent("t\(idx).jpg")
                try TestFixtures.makeJPEG(at: url, size: CGSize(width: 32, height: 24))
                var a = TestFixtures.makeAsset(
                    id: id,
                    baseName: "T\(idx)",
                    captureDate: TestFixtures.makeDate(hour: 11)
                )
                a.previewURL = url
                assets.append(a)
            }

            for a in assets {
                _ = await cache.image(for: a)
            }
            XCTAssertEqual(cache.snapshot().activeMemoryItems, 3)

            let centerID = assets[1].id
            cache.preheatNeighborhood(around: centerID, in: assets, radius: 0)

            let snap = cache.snapshot()
            XCTAssertEqual(snap.activeMemoryItems, 1, "只保留邻域内 1 张")
            XCTAssertGreaterThanOrEqual(snap.trimEvictions, 2)
        }
    }
}
