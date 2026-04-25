import XCTest
@testable import Luma

final class DiscoveredItemIndexingTests: XCTestCase {
    func testDictionaryByResumeKeyLastWinsKeepsLastInArrayOrder() {
        let meta = EXIFData(
            captureDate: TestFixtures.makeDate(hour: 8),
            gpsCoordinate: nil,
            focalLength: 35,
            aperture: 2.0,
            shutterSpeed: "1/125",
            iso: 100,
            cameraModel: "Test",
            lensModel: "Lens",
            imageWidth: 1000,
            imageHeight: 1000
        )
        let source = ImportSource.folder(path: "/tmp")
        let idFirst = UUID()
        let idLast = UUID()
        let first = DiscoveredItem(
            id: idFirst,
            resumeKey: "dup_key",
            baseName: "FIRST",
            source: source,
            previewFile: nil,
            rawFile: nil,
            auxiliaryFile: nil,
            depthData: false,
            metadata: meta,
            mediaType: .photo
        )
        let last = DiscoveredItem(
            id: idLast,
            resumeKey: "dup_key",
            baseName: "LAST",
            source: source,
            previewFile: nil,
            rawFile: nil,
            auxiliaryFile: nil,
            depthData: false,
            metadata: meta,
            mediaType: .photo
        )
        let forward = [first, last].dictionaryByResumeKeyLastWins()
        XCTAssertEqual(forward.count, 1)
        XCTAssertEqual(forward["dup_key"]?.baseName, "LAST")
        XCTAssertEqual(forward["dup_key"]?.id, idLast)

        let backward = [last, first].dictionaryByResumeKeyLastWins()
        XCTAssertEqual(backward["dup_key"]?.baseName, "FIRST")
        XCTAssertEqual(backward["dup_key"]?.id, idFirst)
    }

    func testDictionaryByResumeKeyLastWinsEmptyIsEmpty() {
        let empty: [DiscoveredItem] = []
        XCTAssertTrue(empty.dictionaryByResumeKeyLastWins().isEmpty)
    }
}
