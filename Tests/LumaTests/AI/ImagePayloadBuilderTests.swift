import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Luma

final class ImagePayloadBuilderTests: XCTestCase {

    func testPayloadFromURLDownsamplesLongEdgeAndReturnsBase64() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "ImagePayload") { root in
            let url = root.appendingPathComponent("big.jpg")
            // 4096px 长边 → 应缩到 ≤ 1024px
            try TestFixtures.makeJPEG(at: url, size: CGSize(width: 4096, height: 2048))

            let payload = await ImagePayloadBuilder.payload(from: url)
            let unwrapped = try XCTUnwrap(payload)

            XCTAssertEqual(unwrapped.mimeType, "image/jpeg")
            XCTAssertGreaterThan(unwrapped.longEdgePixels, 0)
            XCTAssertLessThanOrEqual(unwrapped.longEdgePixels, 1024)

            // base64 应可解码回 JPEG，且尺寸与 longEdgePixels 一致
            let decoded = try XCTUnwrap(Data(base64Encoded: unwrapped.base64))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(decoded as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let actualLong = max(image.width, image.height)
            XCTAssertEqual(actualLong, unwrapped.longEdgePixels)
            XCTAssertLessThanOrEqual(actualLong, 1024)
        }
    }

    func testPayloadFromSmallURLDoesNotUpscale() async throws {
        try await TestFixtures.withTemporaryDirectory(prefix: "ImagePayload") { root in
            let url = root.appendingPathComponent("small.jpg")
            try TestFixtures.makeJPEG(at: url, size: CGSize(width: 200, height: 150))

            let payload = await ImagePayloadBuilder.payload(from: url)
            let unwrapped = try XCTUnwrap(payload)
            XCTAssertEqual(unwrapped.longEdgePixels, 200)
        }
    }
}
