import Foundation

struct GeminiProvider: VisionModelProvider {
    let config: ModelConfig

    var id: String { config.id.uuidString }
    var displayName: String { config.name }
    var apiProtocol: APIProtocol { .googleGemini }
    var costPer100Images: Double { 0 }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult {
        let prompts = AIPromptBuilder.groupPrompt(imagesCount: images.count, context: context)
        let body = GeminiRequest(
            contents: [
                .init(parts: [.text(prompts.user)] + images.map {
                    .inlineData(mimeType: $0.mimeType, data: $0.data.base64EncodedString())
                })
            ],
            systemInstruction: .init(parts: [.text(prompts.system)])
        )

        let response = try await performRequest(body: body)
        var result = try ResponseNormalizer.parseGroupScore(provider: config.name, rawText: response.text)
        result = GroupScoreResult(
            photoResults: result.photoResults,
            groupBest: result.groupBest,
            groupComment: result.groupComment,
            usage: response.usage ?? TokenUsage(
                inputTokens: ImagePreprocessor.estimatedInputTokens(for: images),
                outputTokens: max(1, response.text.count / 4)
            )
        )
        return result
    }

    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult {
        let prompts = AIPromptBuilder.detailedPrompt(context: context)
        let body = GeminiRequest(
            contents: [
                .init(parts: [
                    .text(prompts.user),
                    .inlineData(mimeType: image.mimeType, data: image.data.base64EncodedString())
                ])
            ],
            systemInstruction: .init(parts: [.text(prompts.system)])
        )

        let response = try await performRequest(body: body)
        var result = try ResponseNormalizer.parseDetailedAnalysis(rawText: response.text)
        result = DetailedAnalysisResult(
            suggestions: result.suggestions,
            rawResponse: result.rawResponse,
            usage: response.usage ?? TokenUsage(
                inputTokens: max(1, image.data.count / 750),
                outputTokens: max(1, response.text.count / 4)
            )
        )
        return result
    }

    func testConnection() async throws -> Bool {
        let image = try ImagePreprocessor.makeConnectionTestImage()
        let _ = try await scoreGroup(
            images: [image],
            context: GroupContext(groupName: "连接测试", cameraModel: "Luma", lensModel: "Virtual", timeRangeDescription: "Now")
        )
        return true
    }

    private func performRequest(body: GeminiRequest) async throws -> ProviderResponse {
        guard let apiKey = try KeychainHelper.load(service: "Luma.AIModel", account: config.keychainAccount), !apiKey.isEmpty else {
            throw LumaError.configurationInvalid("Missing API key for \(config.name).")
        }

        guard var components = URLComponents(string: normalizedURLString()) else {
            throw LumaError.configurationInvalid("Invalid endpoint for \(config.name).")
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw LumaError.configurationInvalid("Invalid endpoint for \(config.name).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"), !text.isEmpty else {
            throw LumaError.networkFailed("Empty response from \(config.name).")
        }
        return ProviderResponse(
            text: text,
            usage: decoded.usageMetadata?.tokenUsage
        )
    }

    private func normalizedURLString() -> String {
        let endpoint = config.resolvedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.contains(":generateContent") {
            return endpoint
        }
        if endpoint.hasSuffix("/") {
            return endpoint + "v1beta/models/\(config.modelId):generateContent"
        }
        return endpoint + "/v1beta/models/\(config.modelId):generateContent"
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LumaError.networkFailed("Gemini request failed (\(httpResponse.statusCode)): \(body)")
        }
    }
}

private struct GeminiRequest: Encodable {
    let contents: [Content]
    let systemInstruction: Content?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
    }

    struct Content: Encodable {
        let parts: [Part]
    }

    enum Part: Encodable {
        case text(String)
        case inlineData(mimeType: String, data: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode(value, forKey: .text)
            case .inlineData(let mimeType, let data):
                try container.encode(InlineData(mimeType: mimeType, data: data), forKey: .inlineData)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        private struct InlineData: Encodable {
            let mimeType: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case data
            }
        }
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]
    let usageMetadata: UsageMetadata?

    enum CodingKeys: String, CodingKey {
        case candidates
        case usageMetadata = "usageMetadata"
    }

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?

        var tokenUsage: TokenUsage {
            TokenUsage(
                inputTokens: promptTokenCount ?? 0,
                outputTokens: candidatesTokenCount ?? 0
            )
        }
    }
}
