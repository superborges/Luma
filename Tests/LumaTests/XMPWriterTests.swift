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
        XCTAssertTrue(xmp.contains("<crs:Exposure2012>0.35</crs:Exposure2012>"))
        XCTAssertTrue(xmp.contains("<crs:Contrast2012>12</crs:Contrast2012>"))
        XCTAssertTrue(xmp.contains("<crs:Shadows2012>8</crs:Shadows2012>"))
        XCTAssertTrue(xmp.contains("<crs:Temperature>5700</crs:Temperature>"))
        XCTAssertTrue(xmp.contains("<crs:HasCrop>True</crs:HasCrop>"))
        XCTAssertTrue(xmp.contains("<crs:CropAngle>1.2</crs:CropAngle>"))
    }

    func testXMPUsesRDFBagForSubject() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8001",
            captureDate: TestFixtures.makeDate(hour: 10),
            aiScore: TestFixtures.makeAIScore(overall: 70, comment: "Nice shot"),
            userDecision: .picked
        )

        let group = TestFixtures.makeGroup(name: "Tokyo Tower", assets: [asset])

        let xmp = XMPWriter.xmp(for: asset, group: group)

        XCTAssertTrue(xmp.contains("<dc:subject>"))
        XCTAssertTrue(xmp.contains("<rdf:Bag>"))
        XCTAssertTrue(xmp.contains("<rdf:li>Tokyo Tower</rdf:li>"))
        // AI 评语在 dc:description 中，不重复放入 dc:subject 关键词
        XCTAssertFalse(xmp.contains("<rdf:li>AI:"))
    }

    func testXMPUsesRDFAltForDescription() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8002",
            captureDate: TestFixtures.makeDate(hour: 11),
            aiScore: TestFixtures.makeAIScore(overall: 85, comment: "Great composition"),
            userDecision: .picked
        )

        let xmp = XMPWriter.xmp(for: asset, group: nil)

        XCTAssertTrue(xmp.contains("<dc:description>"))
        XCTAssertTrue(xmp.contains("<rdf:Alt>"))
        XCTAssertTrue(xmp.contains("xml:lang=\"x-default\""))
        XCTAssertTrue(xmp.contains("Great composition"))
    }

    func testXMPIncludesIssueLabelsInSubject() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8003",
            captureDate: TestFixtures.makeDate(hour: 12),
            userDecision: .rejected,
            issues: [.blurry, .overexposed]
        )

        let xmp = XMPWriter.xmp(for: asset, group: nil)

        XCTAssertTrue(xmp.contains("xmp:Label=\"Red\""))
        XCTAssertTrue(xmp.contains("<rdf:li>模糊</rdf:li>"))
        XCTAssertTrue(xmp.contains("<rdf:li>过曝</rdf:li>"))
    }

    func testXMPWithoutEditSuggestionsOmitsCRSFields() {
        let suggestions = EditSuggestions(
            crop: CropSuggestion(needed: true, ratio: "16:9", direction: "widen", rule: "center", top: 0.05, bottom: 0.95, left: 0.0, right: 1.0, angle: nil),
            filterStyle: nil,
            adjustments: AdjustmentValues(exposure: 1.5, contrast: 20, highlights: nil, shadows: nil, temperature: nil, tint: nil, saturation: nil, vibrance: nil, clarity: nil, dehaze: nil),
            hslAdjustments: nil,
            localEdits: nil,
            narrative: ""
        )

        var asset = TestFixtures.makeAsset(
            baseName: "IMG_8004",
            captureDate: TestFixtures.makeDate(hour: 14),
            userDecision: .picked
        )
        asset.editSuggestions = suggestions

        let xmp = XMPWriter.xmp(for: asset, group: nil, includeEditSuggestions: false)

        XCTAssertFalse(xmp.contains("crs:Exposure2012"))
        XCTAssertFalse(xmp.contains("crs:HasCrop"))
    }

    func testXMPWithoutAIScoreDefaultsToOneStar() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8005",
            captureDate: TestFixtures.makeDate(hour: 8),
            userDecision: .pending
        )

        let xmp = XMPWriter.xmp(for: asset, group: nil)

        XCTAssertTrue(xmp.contains("xmp:Rating=\"1\""))
        XCTAssertTrue(xmp.contains("xmp:Label=\"Yellow\""))
    }

    func testXMPRatingMappings() {
        func ratingFor(overall: Int) -> String {
            let asset = TestFixtures.makeAsset(
                baseName: "R",
                captureDate: TestFixtures.makeDate(hour: 9),
                aiScore: TestFixtures.makeAIScore(overall: overall),
                userDecision: .picked
            )
            return XMPWriter.xmp(for: asset, group: nil)
        }

        XCTAssertTrue(ratingFor(overall: 95).contains("xmp:Rating=\"5\""))
        XCTAssertTrue(ratingFor(overall: 90).contains("xmp:Rating=\"5\""))
        XCTAssertTrue(ratingFor(overall: 80).contains("xmp:Rating=\"4\""))
        XCTAssertTrue(ratingFor(overall: 65).contains("xmp:Rating=\"3\""))
        XCTAssertTrue(ratingFor(overall: 50).contains("xmp:Rating=\"2\""))
        XCTAssertTrue(ratingFor(overall: 30).contains("xmp:Rating=\"1\""))
    }

    func testXMPHierarchicalSubjectUsesRDFBag() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8006",
            captureDate: TestFixtures.makeDate(hour: 16),
            userDecision: .picked
        )
        let group = TestFixtures.makeGroup(name: "清水寺·日落", assets: [asset])

        let xmp = XMPWriter.xmp(for: asset, group: group)

        XCTAssertTrue(xmp.contains("<lr:hierarchicalSubject>"))
        XCTAssertTrue(xmp.contains("<rdf:li>清水寺·日落</rdf:li>"))
    }

    func testXMPXpacketWrapping() {
        let asset = TestFixtures.makeAsset(
            baseName: "IMG_8007",
            captureDate: TestFixtures.makeDate(hour: 17),
            userDecision: .picked
        )

        let xmp = XMPWriter.xmp(for: asset, group: nil)

        XCTAssertTrue(xmp.contains("<?xpacket begin="))
        XCTAssertTrue(xmp.contains("id=\"W5M0MpCehiHzreSzNTczkc9d\""))
        XCTAssertTrue(xmp.contains("<?xpacket end=\"w\"?>"))
    }
}
