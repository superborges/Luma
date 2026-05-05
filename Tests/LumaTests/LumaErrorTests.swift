import XCTest
@testable import Luma

final class LumaErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertEqual(LumaError.userCancelled.errorDescription, "The operation was cancelled.")
        XCTAssertEqual(LumaError.unsupported("x").errorDescription, "x")
        XCTAssertEqual(LumaError.notImplemented("feat").errorDescription, "feat is not implemented yet.")
        XCTAssertEqual(LumaError.importFailed("bad").errorDescription, "bad")
        XCTAssertEqual(LumaError.persistenceFailed("disk").errorDescription, "disk")
        XCTAssertEqual(LumaError.configurationInvalid("c").errorDescription, "c")
        XCTAssertEqual(LumaError.networkFailed("n").errorDescription, "n")
    }
}
