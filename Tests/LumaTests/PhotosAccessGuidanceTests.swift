import XCTest
@testable import Luma

final class PhotosAccessGuidanceTests: XCTestCase {
    func testIdentifiableIDsAreRawValues() {
        XCTAssertEqual(PhotosAccessGuidance.accessDenied.id, "accessDenied")
        XCTAssertEqual(PhotosAccessGuidance.needFullLibraryRead.id, "needFullLibraryRead")
        XCTAssertEqual(PhotosAccessGuidance.importInProgress.id, "importInProgress")
    }

    func testTitlesAreNonEmpty() {
        for g in [PhotosAccessGuidance.accessDenied, .needFullLibraryRead, .importInProgress] {
            XCTAssertFalse(g.title.isEmpty)
        }
    }

    func testShouldOfferSystemSettingsOnlyForPermissionCases() {
        XCTAssertTrue(PhotosAccessGuidance.accessDenied.shouldOfferSystemSettings)
        XCTAssertTrue(PhotosAccessGuidance.needFullLibraryRead.shouldOfferSystemSettings)
        XCTAssertFalse(PhotosAccessGuidance.importInProgress.shouldOfferSystemSettings)
    }

    func testMessagesAreNonEmpty() {
        for g in [PhotosAccessGuidance.accessDenied, .needFullLibraryRead, .importInProgress] {
            XCTAssertGreaterThan(g.message.count, 20)
        }
    }
}
