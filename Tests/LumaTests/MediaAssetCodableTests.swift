import Foundation
import XCTest
@testable import Luma

final class MediaAssetCodableTests: XCTestCase {
    func testLegacyDecodeFallsBackToLowercasedBaseNameWhenImportResumeKeyMissing() throws {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_9999",
            captureDate: TestFixtures.makeDate(hour: 11, minute: 30),
            importResumeKey: "custom-key"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let encoded = try encoder.encode(asset)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "importResumeKey")

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
        let decoded = try JSONDecoder.lumaDecoder.decode(MediaAsset.self, from: legacyData)

        XCTAssertEqual(decoded.baseName, "IMG_9999")
        XCTAssertEqual(decoded.importResumeKey, "img_9999")
    }

    func testEffectiveRatingPrefersUserRatingAndOtherwiseMapsAIScoreBands() {
        let manualRatingAsset = TestFixtures.makeAsset(
            baseName: "IMG_3001",
            captureDate: TestFixtures.makeDate(hour: 12),
            aiScore: TestFixtures.makeAIScore(overall: 45),
            userRating: 7
        )

        XCTAssertEqual(manualRatingAsset.effectiveRating, 5)

        let cases: [(Int, Int)] = [
            (92, 5),
            (80, 4),
            (60, 3),
            (45, 2),
            (20, 1),
        ]

        for (overall, expectedRating) in cases {
            let asset = TestFixtures.makeAsset(
                baseName: "IMG_\(overall)",
                captureDate: TestFixtures.makeDate(hour: 13),
                aiScore: TestFixtures.makeAIScore(overall: overall)
            )

            XCTAssertEqual(asset.effectiveRating, expectedRating)
        }
    }
}
