import XCTest
@testable import Luma

final class MediaFileScannerTests: XCTestCase {
    func testScanPairsPreviewRawAndAuxiliaryFilesByBaseName() throws {
        try TestFixtures.withTemporaryDirectory { directory in
            let oldDate = TestFixtures.makeDate(hour: 9, minute: 0)
            let newDate = TestFixtures.makeDate(hour: 9, minute: 5)

            let oldPreview = directory.appendingPathComponent("IMG_0001.JPG")
            let newPreview = directory.appendingPathComponent("img_0001.heic")
            let raw = directory.appendingPathComponent("IMG_0001.ARW")
            let liveVideo = directory.appendingPathComponent("IMG_0001.MOV")

            try TestFixtures.createFile(at: oldPreview, modifiedAt: oldDate)
            try TestFixtures.createFile(at: newPreview, modifiedAt: newDate)
            try TestFixtures.createFile(at: raw, modifiedAt: oldDate)
            try TestFixtures.createFile(at: liveVideo, modifiedAt: oldDate)

            let items = try MediaFileScanner.scan(rootFolder: directory, source: .folder(path: directory.path))
            let item = try XCTUnwrap(items.first)

            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(item.resumeKey, "img_0001")
            XCTAssertEqual(item.baseName, "img_0001")
            XCTAssertEqual(item.previewFile?.lastPathComponent, "img_0001.heic")
            XCTAssertEqual(item.rawFile?.lastPathComponent, "IMG_0001.ARW")
            XCTAssertEqual(item.auxiliaryFile?.lastPathComponent, "IMG_0001.MOV")
            XCTAssertEqual(item.mediaType, .livePhoto)
        }
    }

    func testScanSortsByFallbackCaptureDateThenBaseName() throws {
        try TestFixtures.withTemporaryDirectory { directory in
            let sharedDate = TestFixtures.makeDate(hour: 10, minute: 0)
            let laterDate = TestFixtures.makeDate(hour: 10, minute: 5)

            try TestFixtures.createFile(
                at: directory.appendingPathComponent("IMG_0002.JPG"),
                modifiedAt: sharedDate
            )
            try TestFixtures.createFile(
                at: directory.appendingPathComponent("IMG_0001.JPG"),
                modifiedAt: sharedDate
            )
            try TestFixtures.createFile(
                at: directory.appendingPathComponent("IMG_0003.JPG"),
                modifiedAt: laterDate
            )

            let items = try MediaFileScanner.scan(rootFolder: directory, source: .folder(path: directory.path))

            XCTAssertEqual(items.map(\.baseName), ["IMG_0001", "IMG_0002", "IMG_0003"])
        }
    }
}
