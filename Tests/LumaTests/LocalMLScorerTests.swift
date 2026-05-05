import XCTest
@testable import Luma

@MainActor
final class LocalMLScorerTests: XCTestCase {
    func testScoreWithReadablePreviewReturnsPlausibleAssessment() async throws {
        try await TestFixtures.withTemporaryDirectory { dir in
            let url = dir.appendingPathComponent("scorer.jpg")
            try TestFixtures.makeJPEG(at: url)

            var asset = TestFixtures.makeAsset(
                baseName: "S",
                captureDate: TestFixtures.makeDate(hour: 9),
                userDecision: .pending
            )
            asset.previewURL = url

            let scorer = LocalMLScorer()
            let result = await scorer.score(asset: asset)

            XCTAssertGreaterThanOrEqual(result.score, 0)
            XCTAssertLessThanOrEqual(result.score, 100)
            XCTAssertFalse(
                result.issues.contains(.unsupportedFormat),
                "可读 JPEG 不应标记为不支持的格式: \(result.comment)"
            )
        }
    }

    func testScoreWithoutURLsReturnsUnsupportedAssessment() async {
        let asset = TestFixtures.makeAsset(
            baseName: "NoURL",
            captureDate: TestFixtures.makeDate(hour: 9),
            userDecision: .pending
        )
        let r = await LocalMLScorer().score(asset: asset)
        XCTAssertTrue(r.issues.contains(.unsupportedFormat) || r.score < 30)
    }
}
