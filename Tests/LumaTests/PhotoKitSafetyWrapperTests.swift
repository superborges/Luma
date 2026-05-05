import XCTest
@testable import Luma

final class PhotoKitSafetyWrapperTests: XCTestCase {

    func testWithTimeoutReturnsValueWhenOperationFinishesFirst() async {
        let result = await PhotoKitSafetyWrapper.withTimeout(10.0, fallback: -1) {
            42
        }
        XCTAssertEqual(result, 42)
    }

    func testWithTimeoutReturnsFallbackWhenOperationIsSlow() async {
        let result = await PhotoKitSafetyWrapper.withTimeout(0.15, fallback: -1) {
            try? await Task.sleep(for: .seconds(3))
            return 999
        }
        XCTAssertEqual(result, -1)
    }
}
