import Foundation

struct AnthropicProvider: VisionModelProvider {
    let config: ModelConfig

    var id: String { config.id.uuidString }
    var displayName: String { config.name }
    var apiProtocol: APIProtocol { .anthropicMessages }
    var costPer100Images: Double { 0 }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult {
        let prompts = AIPromptBuilder.groupPrompt(imagesCount: images.count, context: context)
        let body = AnthropicRequest(
            model: config.modelId,
            maxTokens: 2048,
            system: prompts.system,
            messages: [
                .init(content: [.text(prompts.user)] + images.map {
                    .image(mediaType: $0.mimeType, data: $0.data.base64EncodedString())
                })
            ]
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
        let body = AnthropicRequest(
            model: config.modelId,
            maxTokens: 2048,
            system: prompts.system,
            messages: [
                .init(content: [
                    .text(prompts.user),
                    .image(mediaType: image.mimeType, data: image.data.base64EncodedString())
                ])
            ]
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

    private func performRequest(body: AnthropicRequest) async throws -> ProviderResponse {
        guard let apiKey = try KeychainHelper.load(service: "Luma.AIModel", account: config.keychainAccount), !apiKey.isEmpty else {
            throw LumaError.configurationInvalid("Missing API key for \(config.name).")
        }

        guard let url = URL(string: config.resolvedEndpoint) else {
            throw LumaError.configurationInvalid("Invalid endpoint for \(config.name).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard !text.isEmpty else {
            throw LumaError.networkFailed("Empty response from \(config.name).")
        }
        return ProviderResponse(
            text: text,
            usage: decoded.usage?.tokenUsage
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LumaError.networkFailed("Anthropic request failed (\(httpResponse.statusCode)): \(body)")
        }
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    struct Message: Encodable {
        let role = "user"
        let content: [Part]
    }

    enum Part: Encodable {
        case text(String)
        case image(mediaType: String, data: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .text)
            case .image(let mediaType, let data):
                try container.encode("image", forKey: .type)
                try container.encode(ImageSource(type: "base64", mediaType: mediaType, data: data), forKey: .source)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case source
        }

        private struct ImageSource: Encodable {
            let type: String
            let mediaType: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case type
                case mediaType = "media_type"
                case data
            }
        }
    }
}

private struct AnthropicResponse: Decodable {
    let content: [ResponsePart]
    let usage: Usage?

    struct ResponsePart: Decodable {
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        var tokenUsage: TokenUsage {
            TokenUsage(inputTokens: inputTokens ?? 0, outputTokens: outputTokens ?? 0)
        }
    }
}
