import Foundation
import XCTest
@testable import Luma

final class SDCardScanInfoTests: XCTestCase {

    func testSDCardImportPromptMessageIncludesPhotoCount() {
        let info = SDCardScanInfo(photoCount: 42, rawFormatSummary: "CR3 ×30、ARW ×12")
        let source = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/CARD", displayName: "EOS R5")
        let prompt = PendingImportPrompt.sdCardImport(source, info)

        XCTAssertTrue(prompt.message.contains("42"))
        XCTAssertTrue(prompt.message.contains("EOS R5"))
        XCTAssertTrue(prompt.message.contains("CR3 ×30"))
        XCTAssertTrue(prompt.isActionable)
        XCTAssertEqual(prompt.confirmTitle, "开始导入")
    }

    func testEmptySDCardPromptNotActionable() {
        let info = SDCardScanInfo(photoCount: 0, rawFormatSummary: "")
        let source = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/EMPTY", displayName: "EMPTY")
        let prompt = PendingImportPrompt.sdCardImport(source, info)

        XCTAssertFalse(prompt.isActionable)
        XCTAssertTrue(prompt.message.contains("未检测到照片"))
    }

    func testSDCardPromptHasCorrectTitle() {
        let info = SDCardScanInfo(photoCount: 10, rawFormatSummary: "")
        let source = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/CARD", displayName: "CARD")
        let prompt = PendingImportPrompt.sdCardImport(source, info)

        XCTAssertEqual(prompt.title, "检测到 SD 卡")
    }

    func testSDCardPromptIDMatchesSourceStableID() {
        let info = SDCardScanInfo(photoCount: 5, rawFormatSummary: "")
        let source = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/X", displayName: "X")
        let prompt = PendingImportPrompt.sdCardImport(source, info)

        XCTAssertEqual(prompt.id, "import:\(source.stableID)")
    }
}
