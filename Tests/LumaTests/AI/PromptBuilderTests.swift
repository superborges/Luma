import XCTest
@testable import Luma

final class PromptBuilderTests: XCTestCase {

    // MARK: - Group scoring prompt

    func testGroupScoringPromptContainsJSONOnlyAndChineseConstraints() {
        let context = GroupContext(
            groupName: "清水寺·日落",
            cameraModel: "Sony A7M4",
            lensModel: "FE 24-70 GM II",
            timeRangeDescription: "17:30 - 18:10"
        )
        let result = PromptBuilder.groupScoringPrompt(context, photoCount: 5)

        XCTAssertTrue(result.system.contains("JSON"), "system 必须强约束 JSON-only 输出")
        XCTAssertTrue(result.system.contains("Chinese") || result.system.contains("简体中文"),
                      "system 必须强约束中文输出")

        XCTAssertTrue(result.user.contains("清水寺·日落"))
        XCTAssertTrue(result.user.contains("Sony A7M4"))
        XCTAssertTrue(result.user.contains("FE 24-70 GM II"))
        XCTAssertTrue(result.user.contains("17:30 - 18:10"))
        XCTAssertTrue(result.user.contains("\"composition\""))
        XCTAssertTrue(result.user.contains("\"group_best\""))
        XCTAssertTrue(result.user.contains("\"group_comment\""))
    }

    /// 方案 A：验证评分锚点 anchoring 出现在 system prompt 中，缓解评分膨胀。
    /// 这些关键字句不应被随便修改——它们是与模型评分尺度对齐的契约。
    func testGroupScoringPromptIncludesScoreDistributionAnchors() {
        let context = GroupContext(groupName: "Test", cameraModel: nil, lensModel: nil, timeRangeDescription: nil)
        let result = PromptBuilder.groupScoringPrompt(context, photoCount: 5)

        // 五段评分锚点的关键数字必须存在
        for anchor in ["90-100", "75-89", "60-74", "40-59", "0-39"] {
            XCTAssertTrue(result.system.contains(anchor),
                          "system 缺少评分锚点 \(anchor)，可能导致评分膨胀回到 V2 初始水平")
        }
        // 严格基调 / 反对扎堆 / recommended 限额等关键约束
        XCTAssertTrue(result.system.contains("STRICT") || result.system.contains("strict"))
        XCTAssertTrue(result.system.contains("DO NOT cluster"))
        XCTAssertTrue(result.system.contains("AT MOST 1-2 photos"))
    }

    func testGroupScoringPromptHandlesMissingMetadata() {
        let context = GroupContext(groupName: "随手", cameraModel: nil, lensModel: nil, timeRangeDescription: nil)
        let result = PromptBuilder.groupScoringPrompt(context, photoCount: 1)
        // 不应崩溃；不应残留空 "Camera: " 之类
        XCTAssertFalse(result.user.contains("Camera: "))
        XCTAssertFalse(result.user.contains("Lens: "))
        XCTAssertFalse(result.user.contains("Time range: "))
        XCTAssertTrue(result.user.contains("随手"))
    }

    // MARK: - Detailed analysis prompt

    func testDetailedAnalysisPromptContainsAllRequiredFields() {
        let exif = EXIFData(
            captureDate: Date(),
            gpsCoordinate: nil,
            focalLength: 35,
            aperture: 1.8,
            shutterSpeed: "1/250",
            iso: 200,
            cameraModel: "Test",
            lensModel: "Test",
            imageWidth: 6000,
            imageHeight: 4000
        )
        let context = PhotoContext(
            baseName: "DSC_0042",
            exif: exif,
            groupName: "京都·清水寺",
            initialOverallScore: 85
        )
        let result = PromptBuilder.detailedAnalysisPrompt(context)

        XCTAssertTrue(result.system.contains("JSON"))
        XCTAssertTrue(result.system.contains("Chinese") || result.system.contains("简体中文"))

        XCTAssertTrue(result.user.contains("DSC_0042"))
        XCTAssertTrue(result.user.contains("f/1.8"))
        XCTAssertTrue(result.user.contains("1/250"))
        XCTAssertTrue(result.user.contains("ISO 200"))
        XCTAssertTrue(result.user.contains("35mm"))
        XCTAssertTrue(result.user.contains("85/100"))
        // 关键字段名（snake_case）应出现在 prompt 模板里
        for field in ["\"crop\"", "\"filter_style\"", "\"adjustments\"", "\"hsl\"", "\"local_edits\"", "\"narrative\""] {
            XCTAssertTrue(result.user.contains(field), "Prompt 缺少字段 \(field)")
        }
    }

    func testDetailedAnalysisPromptOmitsInitialScoreLineWhenNil() {
        let exif = EXIFData(
            captureDate: Date(), gpsCoordinate: nil, focalLength: nil,
            aperture: nil, shutterSpeed: nil, iso: nil,
            cameraModel: nil, lensModel: nil, imageWidth: 0, imageHeight: 0
        )
        let context = PhotoContext(baseName: "X", exif: exif, groupName: "G", initialOverallScore: nil)
        let result = PromptBuilder.detailedAnalysisPrompt(context)
        XCTAssertFalse(result.user.contains("Initial score"))
    }
}
