import XCTest
@testable import Luma

final class AIGroupNamerTests: XCTestCase {

    // MARK: - extractGroupName

    func testExtractGroupNameNormal() {
        let name = AIGroupNamer.extractGroupName(from: "西湖·晨雾", fallback: "fallback")
        XCTAssertEqual(name, "西湖·晨雾")
    }

    func testExtractGroupNameTrimsWhitespace() {
        let name = AIGroupNamer.extractGroupName(from: "  故宫·红墙  \n", fallback: "fallback")
        XCTAssertEqual(name, "故宫·红墙")
    }

    func testExtractGroupNameRemovesQuotes() {
        let name = AIGroupNamer.extractGroupName(from: "\"街头·霓虹\"", fallback: "fallback")
        XCTAssertEqual(name, "街头·霓虹")
    }

    func testExtractGroupNameTruncatesLong() {
        let name = AIGroupNamer.extractGroupName(from: "这是一个超过八个汉字的名称测试", fallback: "fallback")
        XCTAssertEqual(name.count, 8)
        XCTAssertEqual(name, "这是一个超过八个")
    }

    func testExtractGroupNameEmptyReturnsFallback() {
        let name = AIGroupNamer.extractGroupName(from: "", fallback: "原始名称")
        XCTAssertEqual(name, "原始名称")
    }

    func testExtractGroupNameWhitespaceOnlyReturnsFallback() {
        let name = AIGroupNamer.extractGroupName(from: "   \n  ", fallback: "原始名称")
        XCTAssertEqual(name, "原始名称")
    }

    // MARK: - groupNamingPrompt

    func testGroupNamingPromptContainsCurrentName() {
        let prompt = PromptBuilder.groupNamingPrompt(currentName: "2026-04-01 下午", location: nil, photoCount: 5)
        XCTAssertTrue(prompt.user.contains("2026-04-01 下午"))
        XCTAssertTrue(prompt.user.contains("5"))
    }

    func testGroupNamingPromptIncludesLocation() {
        let prompt = PromptBuilder.groupNamingPrompt(currentName: "Test", location: "30.2741, 120.1552", photoCount: 3)
        XCTAssertTrue(prompt.user.contains("30.2741, 120.1552"))
    }

    func testGroupNamingPromptSystemConstraints() {
        let prompt = PromptBuilder.groupNamingPrompt(currentName: "Test", location: nil, photoCount: 1)
        XCTAssertTrue(prompt.system.contains("8"))
        XCTAssertTrue(prompt.system.contains("JSON"))
    }
}
