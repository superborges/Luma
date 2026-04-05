import XCTest
@testable import Luma

final class ResponseNormalizerTests: XCTestCase {
    func testSanitizeJSONEnvelopeRemovesMarkdownFences() {
        let raw = """
        ```json
        { "value": 1 }
        ```
        """

        XCTAssertEqual(ResponseNormalizer.sanitizeJSONEnvelope(raw), "{ \"value\": 1 }")
    }

    func testParseGroupScoreParsesMarkdownWrappedJSON() throws {
        let raw = """
        ```json
        {
          "photos": [
            {
              "index": 1,
              "scores": {
                "composition": 88,
                "exposure": 84,
                "color": 86,
                "sharpness": 91,
                "story": 79
              },
              "overall": 87,
              "comment": "Hero frame",
              "recommended": true
            }
          ],
          "group_best": [1],
          "group_comment": "Keep the first photo."
        }
        ```
        """

        let result = try ResponseNormalizer.parseGroupScore(provider: "ollama", rawText: raw)
        let firstPhoto = try XCTUnwrap(result.photoResults.first)

        XCTAssertEqual(result.groupBest, [1])
        XCTAssertEqual(result.groupComment, "Keep the first photo.")
        XCTAssertEqual(firstPhoto.index, 1)
        XCTAssertEqual(firstPhoto.score.provider, "ollama")
        XCTAssertEqual(firstPhoto.score.scores.sharpness, 91)
        XCTAssertEqual(firstPhoto.score.overall, 87)
        XCTAssertTrue(firstPhoto.score.recommended)
    }

    func testParseDetailedAnalysisFillsDefaultsAndMapsHSLKeys() throws {
        let raw = """
        ```json
        {
          "crop": {
            "needed": true,
            "top": 0.05,
            "bottom": 0.1
          },
          "adjustments": {
            "exposure": 0.35,
            "contrast": 12
          },
          "hsl": [
            {
              "color": "blue",
              "hue": -5,
              "saturation": 10,
              "lum": 20
            }
          ],
          "local_edits": [
            {
              "area": "subject",
              "action": "lift shadows"
            }
          ]
        }
        ```
        """

        let result = try ResponseNormalizer.parseDetailedAnalysis(rawText: raw)
        let crop = try XCTUnwrap(result.suggestions.crop)
        let hsl = try XCTUnwrap(result.suggestions.hslAdjustments?.first)
        let localEdit = try XCTUnwrap(result.suggestions.localEdits?.first)

        XCTAssertEqual(crop.ratio, "4:5")
        XCTAssertEqual(crop.direction, "")
        XCTAssertEqual(crop.rule, "rule_of_thirds")
        XCTAssertEqual(crop.top, 0.05)
        XCTAssertEqual(crop.bottom, 0.1)
        XCTAssertEqual(result.suggestions.adjustments?.exposure, 0.35)
        XCTAssertEqual(result.suggestions.adjustments?.contrast, 12)
        XCTAssertEqual(hsl.color, "blue")
        XCTAssertEqual(hsl.luminance, 20)
        XCTAssertEqual(localEdit.area, "subject")
        XCTAssertEqual(localEdit.action, "lift shadows")
        XCTAssertEqual(result.suggestions.narrative, "未返回修图建议。")
        XCTAssertFalse(result.rawResponse?.contains("```") ?? true)
    }
}
