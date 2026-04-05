import XCTest
@testable import Luma

final class XMPWriterTests: XCTestCase {
    func testXMPIncludesEscapedMetadataAndEditSuggestions() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_7001",
            captureDate: TestFixtures.makeDate(hour: 15),
            aiScore: TestFixtures.makeAIScore(
                overall: 88,
                recommended: true,
                comment: "Bright & \"clean\" <hero>"
            ),
            userDecision: .picked,
            userRating: 4
        )

        let group = TestFixtures.makeGroup(
            name: "Shanghai / Bund & Skyline",
            assets: [asset],
            recommendedAssets: [asset.id]
        )

        let suggestions = EditSuggestions(
            crop: CropSuggestion(
                needed: true,
                ratio: "4:5",
                direction: "tighten",
                rule: "rule_of_thirds",
                top: 0.1,
                bottom: 0.9,
                left: 0.15,
                right: 0.85,
                angle: 1.2
            ),
            filterStyle: nil,
            adjustments: AdjustmentValues(
                exposure: 0.35,
                contrast: 12,
                highlights: nil,
                shadows: 8,
                temperature: 200,
                tint: nil,
                saturation: 5,
                vibrance: 10,
                clarity: nil,
                dehaze: nil
            ),
            hslAdjustments: nil,
            localEdits: nil,
            narrative: "Lift and crop."
        )

        var mutableAsset = asset
        mutableAsset.editSuggestions = suggestions

        let xmp = XMPWriter.xmp(for: mutableAsset, group: group, includeEditSuggestions: true)

        XCTAssertTrue(xmp.contains("xmp:Rating=\"4\""))
        XCTAssertTrue(xmp.contains("xmp:Label=\"Green\""))
        XCTAssertTrue(xmp.contains("Bright &amp; &quot;clean&quot; &lt;hero&gt;"))
        XCTAssertTrue(xmp.contains("lr:hierarchicalSubject=\"Shanghai / Bund &amp; Skyline\""))
        XCTAssertTrue(xmp.contains("<crs:Exposure2012>0.35</crs:Exposure2012>"))
        XCTAssertTrue(xmp.contains("<crs:Contrast2012>12</crs:Contrast2012>"))
        XCTAssertTrue(xmp.contains("<crs:Shadows2012>8</crs:Shadows2012>"))
        XCTAssertTrue(xmp.contains("<crs:Temperature>5700</crs:Temperature>"))
        XCTAssertTrue(xmp.contains("<crs:HasCrop>True</crs:HasCrop>"))
        XCTAssertTrue(xmp.contains("<crs:CropAngle>1.2</crs:CropAngle>"))
    }
}
