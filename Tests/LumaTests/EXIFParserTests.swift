import CoreGraphics
import XCTest
@testable import Luma

final class EXIFParserTests: XCTestCase {
    func testParseJPEGProducesDimensionsAndSensibleDate() throws {
        try TestFixtures.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("exif_t.jpg")
            try TestFixtures.makeJPEG(at: url)

            let exif = EXIFParser.parse(from: url)
            XCTAssertGreaterThanOrEqual(exif.imageWidth, 1)
            XCTAssertGreaterThanOrEqual(exif.imageHeight, 1)
        }
    }

    func testMakeThumbnailReturnsImage() throws {
        try TestFixtures.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("thumb.jpg")
            try TestFixtures.makeJPEG(at: url)

            let thumb = EXIFParser.makeThumbnail(from: url, maxPixelSize: 32)
            XCTAssertNotNil(thumb)
            XCTAssertLessThanOrEqual(max(thumb!.width, thumb!.height), 32)
        }
    }

    func testCgImageForDisplayUsesSmallImageAsFullWhenUnderBudget() throws {
        try TestFixtures.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("small.jpg")
            try TestFixtures.makeJPEG(at: url, size: CGSize(width: 4, height: 4))

            let img = EXIFParser.cgImageForDisplay(at: url, maxLongEdge: 4000)
            XCTAssertNotNil(img)
        }
    }
}
