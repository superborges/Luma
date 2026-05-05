import Foundation
import XCTest
@testable import Luma

final class RAWJPEGPairerTests: XCTestCase {

    private func makeFile(
        name: String,
        ext: String,
        category: DCIMScanner.Category,
        dir: String = "100CANON"
    ) -> DCIMScanner.ScannedFile {
        DCIMScanner.ScannedFile(
            url: URL(filePath: "/Volumes/CARD/DCIM/\(dir)/\(name).\(ext)"),
            baseKey: name.lowercased(),
            modifiedAt: Date(),
            category: category
        )
    }

    func testPairsRAWAndJPEGBySameBaseName() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0001", ext: "jpg", category: .preview),
            makeFile(name: "IMG_0001", ext: "CR3", category: .raw(ext: "CR3")),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertNotNil(item.previewFile)
        XCTAssertNotNil(item.rawFile)
        XCTAssertEqual(item.previewFile?.pathExtension, "jpg")
        XCTAssertEqual(item.rawFile?.pathExtension, "CR3")
    }

    func testRAWOnlyItemHasNilPreviewFile() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "DSC_0001", ext: "NEF", category: .raw(ext: "NEF")),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].previewFile)
        XCTAssertNotNil(items[0].rawFile)
    }

    func testJPEGOnlyItemHasNilRawFile() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0002", ext: "jpg", category: .preview),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items.count, 1)
        XCTAssertNotNil(items[0].previewFile)
        XCTAssertNil(items[0].rawFile)
    }

    func testCrossSubdirectoryPairing() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0001", ext: "jpg", category: .preview, dir: "100CANON"),
            makeFile(name: "IMG_0001", ext: "CR3", category: .raw(ext: "CR3"), dir: "101CANON"),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items.count, 1)
        XCTAssertNotNil(items[0].previewFile)
        XCTAssertNotNil(items[0].rawFile)
    }

    func testVideoFilesAsAuxiliary() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0003", ext: "jpg", category: .preview),
            makeFile(name: "IMG_0003", ext: "mov", category: .video),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items.count, 1)
        XCTAssertNotNil(items[0].auxiliaryFile)
        XCTAssertEqual(items[0].mediaType, .livePhoto)
    }

    func testMultipleUnrelatedFilesProduceMultipleItems() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0001", ext: "jpg", category: .preview),
            makeFile(name: "IMG_0002", ext: "CR3", category: .raw(ext: "CR3")),
            makeFile(name: "IMG_0003", ext: "heic", category: .preview),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items.count, 3)
    }

    func testOutputContainsAllInputBaseNames() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0003", ext: "jpg", category: .preview),
            makeFile(name: "IMG_0001", ext: "jpg", category: .preview),
            makeFile(name: "IMG_0002", ext: "jpg", category: .preview),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        let names = Set(items.map(\.baseName))
        XCTAssertEqual(names, ["IMG_0001", "IMG_0002", "IMG_0003"])
    }

    func testImportSourceIsSDCard() {
        let files: [DCIMScanner.ScannedFile] = [
            makeFile(name: "IMG_0001", ext: "jpg", category: .preview),
        ]

        let items = RAWJPEGPairer.pair(files: files, source: .sdCard(volumePath: "/Volumes/CARD"))

        XCTAssertEqual(items[0].source, .sdCard(volumePath: "/Volumes/CARD"))
    }
}
