import Foundation
import XCTest
@testable import Luma

final class DCIMScannerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createFile(_ relativePath: String, content: Data = Data([0xFF])) {
        let url = tempDir.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try! content.write(to: url)
    }

    // MARK: - DCIMScanner

    func testScanFindsAllSupportedExtensions() throws {
        createFile("100CANON/IMG_0001.jpg")
        createFile("100CANON/IMG_0001.CR3")
        createFile("100CANON/IMG_0002.ARW")
        createFile("100CANON/IMG_0003.heic")
        createFile("100CANON/IMG_0004.NEF")
        createFile("100CANON/IMG_0005.DNG")
        createFile("100CANON/IMG_0006.RAF")
        createFile("100CANON/IMG_0007.ORF")
        createFile("100CANON/IMG_0008.RW2")
        createFile("100CANON/IMG_0009.mov")
        createFile("100CANON/readme.txt")

        let files = try DCIMScanner.scan(dcimRoot: tempDir)

        XCTAssertEqual(files.count, 10)

        let extensions = Set(files.map { $0.url.pathExtension.lowercased() })
        XCTAssertTrue(extensions.contains("jpg"))
        XCTAssertTrue(extensions.contains("cr3"))
        XCTAssertTrue(extensions.contains("arw"))
        XCTAssertTrue(extensions.contains("heic"))
        XCTAssertTrue(extensions.contains("nef"))
        XCTAssertTrue(extensions.contains("dng"))
        XCTAssertTrue(extensions.contains("raf"))
        XCTAssertTrue(extensions.contains("orf"))
        XCTAssertTrue(extensions.contains("rw2"))
        XCTAssertTrue(extensions.contains("mov"))
        XCTAssertFalse(extensions.contains("txt"))
    }

    func testScanCategoriesAreCorrect() throws {
        createFile("100CANON/IMG_0001.jpg")
        createFile("100CANON/IMG_0002.CR3")
        createFile("100CANON/IMG_0003.mov")

        let files = try DCIMScanner.scan(dcimRoot: tempDir)

        let preview = files.first { $0.url.pathExtension.lowercased() == "jpg" }
        let raw = files.first { $0.url.pathExtension.lowercased() == "cr3" }
        let video = files.first { $0.url.pathExtension.lowercased() == "mov" }

        XCTAssertEqual(preview?.category, .preview)
        XCTAssertEqual(raw?.category, .raw(ext: "CR3"))
        XCTAssertEqual(video?.category, .video)
    }

    func testScanRecursesSubdirectories() throws {
        createFile("100CANON/IMG_0001.jpg")
        createFile("101NIKON/DSC_0001.nef")
        createFile("102SONY/deep/nested/IMG_0001.arw")

        let files = try DCIMScanner.scan(dcimRoot: tempDir)
        XCTAssertEqual(files.count, 3)
    }

    func testQuickSummaryComputesCorrectCounts() {
        createFile("100CANON/IMG_0001.jpg")
        createFile("100CANON/IMG_0001.CR3")
        createFile("100CANON/IMG_0002.CR3")
        createFile("100CANON/IMG_0003.ARW")
        createFile("100CANON/IMG_0004.mov")

        let summary = DCIMScanner.quickSummary(dcimRoot: tempDir)

        XCTAssertEqual(summary.videoCount, 1)
        XCTAssertEqual(summary.rawFormatDistribution["CR3"], 2)
        XCTAssertEqual(summary.rawFormatDistribution["ARW"], 1)
        // unique baseKeys: img_0001 (jpg+cr3), img_0002 (cr3), img_0003 (arw) = 3
        XCTAssertEqual(summary.photoCount, 3)
    }

    func testQuickSummaryReturnsEmptyForMissingDir() {
        let missing = tempDir.appendingPathComponent("nonexistent")
        let summary = DCIMScanner.quickSummary(dcimRoot: missing)
        XCTAssertTrue(summary.isEmpty)
    }
}
