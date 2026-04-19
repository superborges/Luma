import Foundation

struct OpenAICompatibleProvider: VisionModelProvider {
    let config: ModelConfig

    var id: String { config.id.uuidString }
    var displayName: String { config.name }
    var apiProtocol: APIProtocol { .openAICompatible }
    var costPer100Images: Double { 0 }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult {
        let prompts = AIPromptBuilder.groupPrompt(imagesCount: images.count, context: context)
        let body = OpenAIChatRequest(
            model: config.modelId,
            messages: [
                .init(role: "system", content: .string(prompts.system)),
                .init(role: "user", content: .parts([
                    .text(prompts.user),
                ] + images.map {
                    .imageURL("data:\($0.mimeType);base64,\($0.data.base64EncodedString())")
                }))
            ],
            responseFormat: .init(type: "json_object")
        )

        let rawResponse = try await performRequest(body: body)
        var result = try ResponseNormalizer.parseGroupScore(provider: config.name, rawText: rawResponse.text)
        result = GroupScoreResult(
            photoResults: result.photoResults,
            groupBest: result.groupBest,
            groupComment: result.groupComment,
            usage: rawResponse.usage ?? TokenUsage(
                inputTokens: ImagePreprocessor.estimatedInputTokens(for: images),
                outputTokens: max(1, rawResponse.text.count / 4)
            )
        )
        return result
    }

    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult {
        let prompts = AIPromptBuilder.detailedPrompt(context: context)
        let body = OpenAIChatRequest(
            model: config.modelId,
            messages: [
                .init(role: "system", content: .string(prompts.system)),
                .init(role: "user", content: .parts([
                    .text(prompts.user),
                    .imageURL("data:\(image.mimeType);base64,\(image.data.base64EncodedString())")
                ]))
            ],
            responseFormat: .init(type: "json_object")
        )

        let rawResponse = try await performRequest(body: body)
        var result = try ResponseNormalizer.parseDetailedAnalysis(rawText: rawResponse.text)
        result = DetailedAnalysisResult(
            suggestions: result.suggestions,
            rawResponse: result.rawResponse,
            usage: rawResponse.usage ?? TokenUsage(
                inputTokens: max(1, image.data.count / 750),
                outputTokens: max(1, rawResponse.text.count / 4)
            )
        )
        return result
    }

    func testConnection() async throws -> Bool {
        let testImage = try ImagePreprocessor.makeConnectionTestImage()
        let prompts = AIPromptBuilder.groupPrompt(
            imagesCount: 1,
            context: GroupContext(groupName: "连接测试", cameraModel: "Luma", lensModel: "Virtual", timeRangeDescription: "Now")
        )

        let body = OpenAIChatRequest(
            model: config.modelId,
            messages: [
                .init(role: "system", content: .string(prompts.system)),
                .init(role: "user", content: .parts([
                    .text(prompts.user),
                    .imageURL("data:\(testImage.mimeType);base64,\(testImage.data.base64EncodedString())")
                ]))
            ],
            responseFormat: .init(type: "json_object")
        )

        let response = try await performRequest(body: body)
        _ = try ResponseNormalizer.parseGroupScore(provider: config.name, rawText: response.text)
        return true
    }

    private func performRequest(body: OpenAIChatRequest) async throws -> ProviderResponse {
        guard let url = URL(string: normalizedURLString()) else {
            throw LumaError.configurationInvalid("Invalid endpoint for \(config.name).")
        }

        let apiKey = try KeychainHelper.load(service: "Luma.AIModel", account: config.keychainAccount)
        if !isLocalOllamaEndpoint(url), (apiKey?.isEmpty ?? true) {
            throw LumaError.configurationInvalid("Missing API key for \(config.name).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let firstChoice = decoded.choices.first else {
            throw LumaError.networkFailed("Empty response from \(config.name).")
        }
        return ProviderResponse(
            text: firstChoice.message.content.textValue,
            usage: decoded.usage?.tokenUsage
        )
    }

    private func normalizedURLString() -> String {
        let endpoint = config.resolvedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint == "http://127.0.0.1:11434" || endpoint == "http://localhost:11434" {
            return endpoint + "/v1/chat/completions"
        }
        if endpoint.hasSuffix("/chat/completions") {
            return endpoint
        }
        if endpoint.hasSuffix("/v1") {
            return endpoint + "/chat/completions"
        }
        return endpoint + "/chat/completions"
    }

    private func isLocalOllamaEndpoint(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return (host == "127.0.0.1" || host == "localhost") && url.port == 11434
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LumaError.networkFailed("OpenAI-compatible request failed (\(httpResponse.statusCode)): \(body)")
        }
    }
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: Content

    enum Content: Encodable {
        case string(String)
        case parts([Part])

        func encode(to encoder: Encoder) throws {
            switch self {
            case .string(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .parts(let parts):
                var container = encoder.unkeyedContainer()
                for part in parts {
                    try container.encode(part)
                }
            }
        }
    }

    enum Part: Encodable {
        case text(String)
        case imageURL(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURL(url: url), forKey: .imageURL)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        private struct ImageURL: Encodable {
            let url: String
        }
    }
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: MessageContent
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }

        var tokenUsage: TokenUsage {
            TokenUsage(inputTokens: promptTokens ?? 0, outputTokens: completionTokens ?? 0)
        }
    }
}

private enum MessageContent: Decodable {
    case string(String)
    case parts([ContentPart])

    var textValue: String {
        switch self {
        case .string(let value):
            return value
        case .parts(let parts):
            return parts.compactMap(\.text).joined(separator: "\n")
        }
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            self = .string(string)
        } else {
            self = .parts(try single.decode([ContentPart].self))
        }
    }
}

private struct ContentPart: Decodable {
    let type: String?
    let text: String?
}
