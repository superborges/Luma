import XCTest
@testable import Luma

final class ResponseNormalizerTests: XCTestCase {

    // MARK: - Markdown fence

    func testStripMarkdownFencesRemovesJSONFence() {
        let raw = """
        ```json
        {"a": 1}
        ```
        """
        XCTAssertEqual(ResponseNormalizer.stripMarkdownFences(raw), "{\"a\": 1}")
    }

    func testStripMarkdownFencesRemovesBareFence() {
        let raw = "```\n{\"a\":1}\n```"
        XCTAssertEqual(ResponseNormalizer.stripMarkdownFences(raw), "{\"a\":1}")
    }

    func testStripMarkdownFencesNoOpWhenNoFence() {
        XCTAssertEqual(ResponseNormalizer.stripMarkdownFences("{\"a\":1}"), "{\"a\":1}")
    }

    func testStripMarkdownFencesTrimsWhitespace() {
        XCTAssertEqual(ResponseNormalizer.stripMarkdownFences("  \n {\"a\":1}\n  "), "{\"a\":1}")
    }

    // MARK: - OpenAI 兼容: Group score

    func testOpenAIGroupScoreNormalizes() throws {
        let modelJSON = """
        {"photos":[{"index":1,"scores":{"composition":80,"exposure":70,"color":75,"sharpness":85,"story":60},"overall":74,"comment":"构图不错","recommended":true}],"group_best":[1],"group_comment":"整组主题清晰"}
        """
        let envelope = """
        {"choices":[{"message":{"content":"\(escape(modelJSON))"}}],"usage":{"prompt_tokens":1200,"completion_tokens":300}}
        """
        let data = envelope.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: .openAICompatible)
        let value = try unwrap(result)
        XCTAssertEqual(value.perPhoto.count, 1)
        XCTAssertEqual(value.perPhoto[0].scores.composition, 80)
        XCTAssertEqual(value.groupBest, [1])
        XCTAssertEqual(value.groupComment, "整组主题清晰")
        XCTAssertEqual(value.usage.inputTokens, 1200)
        XCTAssertEqual(value.usage.outputTokens, 300)
    }

    func testOpenAIGroupScoreToleratesMarkdownFenceInContent() throws {
        let modelJSON = "```json\n{\"photos\":[],\"group_best\":[],\"group_comment\":\"empty\"}\n```"
        let envelope = """
        {"choices":[{"message":{"content":"\(escape(modelJSON))"}}],"usage":{"prompt_tokens":10,"completion_tokens":5}}
        """
        let data = envelope.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: .openAICompatible)
        _ = try unwrap(result)
    }

    // MARK: - Gemini: Group score

    func testGeminiGroupScoreNormalizes() throws {
        let modelJSON = """
        {"photos":[{"index":1,"scores":{"composition":50,"exposure":60,"color":70,"sharpness":40,"story":30},"overall":50,"comment":"还行","recommended":false}],"group_best":[],"group_comment":"待提升"}
        """
        let envelope = """
        {"candidates":[{"content":{"parts":[{"text":"\(escape(modelJSON))"}]}}],"usageMetadata":{"promptTokenCount":2000,"candidatesTokenCount":150}}
        """
        let data = envelope.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: .googleGemini)
        let value = try unwrap(result)
        XCTAssertEqual(value.usage.inputTokens, 2000)
        XCTAssertEqual(value.usage.outputTokens, 150)
        XCTAssertEqual(value.groupComment, "待提升")
    }

    // MARK: - Anthropic: Group score

    func testAnthropicGroupScoreNormalizes() throws {
        let modelJSON = """
        {"photos":[{"index":2,"scores":{"composition":90,"exposure":85,"color":88,"sharpness":92,"story":70},"overall":85,"comment":"主体突出","recommended":true}],"group_best":[2],"group_comment":"整体优秀"}
        """
        let envelope = """
        {"content":[{"text":"\(escape(modelJSON))"}],"usage":{"input_tokens":3000,"output_tokens":250}}
        """
        let data = envelope.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: .anthropicMessages)
        let value = try unwrap(result)
        XCTAssertEqual(value.usage.inputTokens, 3000)
        XCTAssertEqual(value.usage.outputTokens, 250)
        XCTAssertTrue(value.perPhoto[0].recommended)
    }

    // MARK: - Detailed analysis

    func testGeminiDetailedAnalysisNormalizes() throws {
        let modelJSON = """
        {"crop":{"needed":true,"ratio":"16:9","direction":"略向左裁","rule":"rule_of_thirds","top":0.0,"bottom":1.0,"left":0.05,"right":0.95},"filter_style":{"primary":"warm_golden_hour","reference":"VSCO A6","mood":"温暖怀旧"},"adjustments":{"exposure":0.3,"contrast":10,"highlights":-20,"shadows":15,"temperature":300,"tint":-5,"saturation":5,"vibrance":10,"clarity":5,"dehaze":0},"hsl":[{"color":"orange","hue":-5,"saturation":15,"luminance":0}],"local_edits":[{"area":"天空","action":"压暗高光"}],"narrative":"整体氛围温暖怀旧。"}
        """
        let envelope = """
        {"candidates":[{"content":{"parts":[{"text":"\(escape(modelJSON))"}]}}],"usageMetadata":{"promptTokenCount":500,"candidatesTokenCount":300}}
        """
        let data = envelope.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeDetailedAnalysisResponse(data, apiProtocol: .googleGemini)
        let value = try unwrap(result)
        XCTAssertEqual(value.crop?.ratio, "16:9")
        XCTAssertEqual(value.filterStyle?.primary, "warm_golden_hour")
        XCTAssertEqual(value.adjustments?.exposure, 0.3)
        XCTAssertEqual(value.hsl?.first?.color, "orange")
        XCTAssertEqual(value.localEdits?.first?.area, "天空")
        XCTAssertEqual(value.narrative, "整体氛围温暖怀旧。")
    }

    // MARK: - 字段缺失容忍

    func testGroupScoreToleratesMissingOptionalFields() throws {
        // 模型漏 comment / recommended / group_best / group_comment
        let modelJSON = """
        {"photos":[{"index":1,"scores":{"composition":80,"exposure":70,"color":75,"sharpness":85,"story":60},"overall":74}]}
        """
        let envelope = """
        {"choices":[{"message":{"content":"\(escape(modelJSON))"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
        """
        let data = envelope.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: .openAICompatible)
        let value = try unwrap(result)
        XCTAssertEqual(value.perPhoto.count, 1)
        XCTAssertEqual(value.perPhoto[0].comment, "")
        XCTAssertFalse(value.perPhoto[0].recommended)
        XCTAssertEqual(value.groupBest, [])
        XCTAssertEqual(value.groupComment, "")
    }

    // MARK: - 错误路径

    func testProtocolMismatchWhenFieldMissing() {
        let envelope = "{\"unrelated\":true}".data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(envelope, apiProtocol: .openAICompatible)
        switch result {
        case .success: XCTFail("应失败")
        case .failure(let error):
            if case .protocolMismatch = error {} else {
                XCTFail("应为 protocolMismatch，实为 \(error)")
            }
        }
    }

    func testMalformedJSONWhenContentBroken() {
        let envelope = """
        {"choices":[{"message":{"content":"this is not json"}}]}
        """.data(using: .utf8)!
        let result = ResponseNormalizer.normalizeGroupScoreResponse(envelope, apiProtocol: .openAICompatible)
        switch result {
        case .success: XCTFail("应失败")
        case .failure(let error):
            if case .malformedJSON = error {} else {
                XCTFail("应为 malformedJSON，实为 \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// 把 JSON 字符串转义为可嵌入到外层 JSON `"..."` 的形式。
    private func escape(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["v": s])
        let text = String(data: data, encoding: .utf8)!
        // 取出 "v":"..." 中 ... 部分
        let prefix = "{\"v\":\""
        var trimmed = text
        if trimmed.hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count))
        }
        if trimmed.hasSuffix("\"}") {
            trimmed = String(trimmed.dropLast(2))
        }
        return trimmed
    }

    private func unwrap<T>(_ result: Result<T, NormalizerError>) throws -> T {
        switch result {
        case .success(let v): return v
        case .failure(let e):
            XCTFail("Normalizer 失败：\(e)")
            throw e
        }
    }
}
