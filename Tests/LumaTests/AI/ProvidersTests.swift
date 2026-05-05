import XCTest
@testable import Luma

/// Provider 单测：验证三种协议构造的 URLRequest 路径 / Header / Body 形状是否符合预期。
/// 不真打外部 API；用 `MockHTTPClient` + 预设响应 stub。
final class ProvidersTests: XCTestCase {

    // MARK: - 公共 fixture

    private func makeImage() -> ProviderImagePayload {
        ProviderImagePayload(base64: "AAAA", longEdgePixels: 1024, mimeType: "image/jpeg")
    }

    private func makeContext() -> GroupContext {
        GroupContext(groupName: "测试组", cameraModel: "Cam", lensModel: "Lens", timeRangeDescription: nil)
    }

    private func makePhotoContext() -> PhotoContext {
        let exif = EXIFData(
            captureDate: Date(),
            gpsCoordinate: nil,
            focalLength: 35,
            aperture: 1.8,
            shutterSpeed: "1/250",
            iso: 200,
            cameraModel: "Cam",
            lensModel: "Lens",
            imageWidth: 6000,
            imageHeight: 4000
        )
        return PhotoContext(baseName: "X", exif: exif, groupName: "G", initialOverallScore: 80)
    }

    /// 把 model 输出 JSON 转义嵌入到外层 JSON 字符串（与 ResponseNormalizerTests 一致）。
    private func escape(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["v": s])
        let text = String(data: data, encoding: .utf8)!
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

    private let validGroupModelJSON = """
    {"photos":[{"index":1,"scores":{"composition":80,"exposure":70,"color":75,"sharpness":85,"story":60},"overall":74,"comment":"OK","recommended":true}],"group_best":[1],"group_comment":"OK"}
    """

    // MARK: - OpenAI 兼容

    func testOpenAIRequestShape() async throws {
        let mock = MockHTTPClient()
        let envelope = """
        {"choices":[{"message":{"content":"\(escape(validGroupModelJSON))"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
        """
        mock.stub(pathContains: "chat/completions", body: envelope.data(using: .utf8)!)

        let config = ModelConfig(
            name: "GPT-4o", apiProtocol: .openAICompatible,
            endpoint: "https://api.openai.com/v1/", modelID: "gpt-4o"
        )
        let provider = OpenAICompatibleProvider(config: config, apiKey: "sk-test", httpClient: mock)
        _ = try await provider.scoreGroup(images: [makeImage()], context: makeContext())

        XCTAssertEqual(mock.sentRequests.count, 1)
        let req = mock.sentRequests[0]
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gpt-4o")
        let messages = json?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?[0]["role"] as? String, "system")
        XCTAssertEqual(messages?[1]["role"] as? String, "user")
        // user content 必须为多模态数组
        let userContent = messages?[1]["content"] as? [[String: Any]]
        XCTAssertNotNil(userContent)
        XCTAssertEqual(userContent?.first?["type"] as? String, "text")
        XCTAssertEqual(userContent?.last?["type"] as? String, "image_url")
    }

    // MARK: - Gemini

    func testGeminiRequestShape() async throws {
        let mock = MockHTTPClient()
        let envelope = """
        {"candidates":[{"content":{"parts":[{"text":"\(escape(validGroupModelJSON))"}]}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1}}
        """
        mock.stub(pathContains: ":generateContent", body: envelope.data(using: .utf8)!)

        let config = ModelConfig(
            name: "Gemini Flash", apiProtocol: .googleGemini,
            endpoint: "https://generativelanguage.googleapis.com",
            modelID: "gemini-2.0-flash"
        )
        let provider = GoogleGeminiProvider(config: config, apiKey: "g-key", httpClient: mock)
        _ = try await provider.scoreGroup(images: [makeImage()], context: makeContext())

        XCTAssertEqual(mock.sentRequests.count, 1)
        let req = mock.sentRequests[0]
        let urlString = req.url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("v1beta/models/gemini-2.0-flash:generateContent"))
        XCTAssertTrue(urlString.contains("key=g-key"))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let contents = json?["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        XCTAssertGreaterThanOrEqual(parts?.count ?? 0, 2, "应至少包含 1 个 text + 1 个 inline_data")
        XCTAssertNotNil(parts?.last?["inline_data"])
    }

    // MARK: - Anthropic

    func testAnthropicRequestShape() async throws {
        let mock = MockHTTPClient()
        let envelope = """
        {"content":[{"text":"\(escape(validGroupModelJSON))"}],"usage":{"input_tokens":1,"output_tokens":1}}
        """
        mock.stub(pathContains: "/messages", body: envelope.data(using: .utf8)!)

        let config = ModelConfig(
            name: "Claude", apiProtocol: .anthropicMessages,
            endpoint: "https://api.anthropic.com/v1",
            modelID: "claude-3-5-sonnet-20241022"
        )
        let provider = AnthropicMessagesProvider(config: config, apiKey: "anth-key", httpClient: mock)
        _ = try await provider.scoreGroup(images: [makeImage()], context: makeContext())

        XCTAssertEqual(mock.sentRequests.count, 1)
        let req = mock.sentRequests[0]
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "anth-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try XCTUnwrap(req.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "claude-3-5-sonnet-20241022")
        XCTAssertNotNil(json?["system"])
        let messages = json?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        XCTAssertTrue(content?.contains(where: { $0["type"] as? String == "image" }) ?? false)
        XCTAssertTrue(content?.contains(where: { $0["type"] as? String == "text" }) ?? false)
    }

    // MARK: - Detailed analysis 路径覆盖

    func testOpenAIDetailedAnalysisRequest() async throws {
        let mock = MockHTTPClient()
        let detailedJSON = """
        {"crop":null,"filter_style":null,"adjustments":null,"hsl":null,"local_edits":null,"narrative":"OK"}
        """
        let envelope = """
        {"choices":[{"message":{"content":"\(escape(detailedJSON))"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
        """
        mock.stub(pathContains: "chat/completions", body: envelope.data(using: .utf8)!)

        let config = ModelConfig(
            name: "GPT-4o", apiProtocol: .openAICompatible,
            endpoint: "https://api.openai.com/v1", modelID: "gpt-4o"
        )
        let provider = OpenAICompatibleProvider(config: config, apiKey: "sk", httpClient: mock)
        let result = try await provider.detailedAnalysis(image: makeImage(), context: makePhotoContext())
        XCTAssertEqual(result.narrative, "OK")
    }

    // MARK: - Endpoint 解析

    func testParseEndpointStripsWhitespaceAndTrailingSlashes() throws {
        let url = try ProviderHTTPSupport.parseEndpoint("  https://api.openai.com/v1//  ")
        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1")
    }

    func testParseEndpointRejectsEmptyOrInvalid() {
        XCTAssertThrowsError(try ProviderHTTPSupport.parseEndpoint(""))
        XCTAssertThrowsError(try ProviderHTTPSupport.parseEndpoint("ftp://x"))
        XCTAssertThrowsError(try ProviderHTTPSupport.parseEndpoint("not a url"))
    }

    // MARK: - 错误传播

    func testHTTPErrorPropagatesAsAIProvider() async throws {
        let mock = MockHTTPClient()
        mock.stub(pathContains: "chat/completions", status: 401, body: Data("invalid api key".utf8))

        let config = ModelConfig(
            name: "GPT", apiProtocol: .openAICompatible,
            endpoint: "https://api.openai.com/v1", modelID: "gpt-4o"
        )
        let provider = OpenAICompatibleProvider(config: config, apiKey: "bad", httpClient: mock)
        do {
            _ = try await provider.scoreGroup(images: [makeImage()], context: makeContext())
            XCTFail("应抛错")
        } catch let LumaError.aiProvider(code, message) {
            XCTAssertEqual(code, 401)
            XCTAssertTrue(
                message.contains("API Key 无效") || message.contains("API Key"),
                "401 错误应映射成中文友好提示，实际消息：\(message)"
            )
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    /// DeepSeek 等"OpenAI 兼容但不支持 vision"的服务返回的典型错误：
    /// `unknown variant 'image_url', expected 'text'`。应被识别成"模型不支持视觉输入"。
    func testHTTPVisionUnsupportedErrorIsHumanReadable() async throws {
        let mock = MockHTTPClient()
        let body = "{\"error\":{\"message\":\"unknown variant `image_url`, expected `text`\"}}"
        mock.stub(pathContains: "chat/completions", status: 400, body: Data(body.utf8))

        let config = ModelConfig(
            name: "DeepSeek", apiProtocol: .openAICompatible,
            endpoint: "https://api.deepseek.com", modelID: "deepseek-chat"
        )
        let provider = OpenAICompatibleProvider(config: config, apiKey: "sk", httpClient: mock)
        do {
            _ = try await provider.scoreGroup(images: [makeImage()], context: makeContext())
            XCTFail("应抛错")
        } catch let LumaError.aiProvider(_, message) {
            XCTAssertTrue(message.contains("不支持视觉"), "消息应包含中文「不支持视觉」诊断，实际：\(message)")
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    // MARK: - 测试连接

    func testConnectionTestForOpenAI() async throws {
        let mock = MockHTTPClient()
        let envelope = """
        {"choices":[{"message":{"content":"pong"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
        """
        mock.stub(pathContains: "chat/completions", body: envelope.data(using: .utf8)!)

        let config = ModelConfig(
            name: "GPT", apiProtocol: .openAICompatible,
            endpoint: "https://api.openai.com/v1", modelID: "gpt-4o"
        )
        let provider = OpenAICompatibleProvider(config: config, apiKey: "sk", httpClient: mock)
        let ok = try await provider.testConnection()
        XCTAssertTrue(ok)
    }
}
