import XCTest
@testable import Luma

final class AppDirectoriesSanitizeTests: XCTestCase {
    func testSanitizePathStripsSlashesAndIllegalChars() {
        XCTAssertEqual(
            AppDirectories.sanitizePathComponent("a/b:c"),
            "a-b-c"
        )
    }

    func testSanitizeFallsBackWhenInputEmptyAfterStripping() {
        XCTAssertEqual(AppDirectories.sanitizePathComponent(""), "Luma_Project")
    }
}
