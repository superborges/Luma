import Foundation

/// Google Gemini Vision Provider。
///
/// 请求形态：`POST {endpoint}/v1beta/models/{model}:generateContent?key={apiKey}`，
/// 图像走 `inline_data { mime_type, data }`，data 是 base64 字符串。
struct GoogleGeminiProvider: VisionModelProvider {
    let id: String
    let displayName: String
    let endpoint: String
    let modelID: String
    let apiKey: String
    let httpClient: HTTPClient

    var apiProtocol: APIProtocol { .googleGemini }

    init(config: ModelConfig, apiKey: String, httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.id = config.id.uuidString
        self.displayName = config.name
        self.endpoint = config.endpoint
        self.modelID = config.modelID
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - VisionModelProvider

    func scoreGroup(images: [ProviderImagePayload], context: GroupContext) async throws -> GroupScoreResult {
        let prompt = PromptBuilder.groupScoringPrompt(context, photoCount: images.count)
        let body = try buildRequestBody(systemPrompt: prompt.system, userPrompt: prompt.user, images: images)
        let request = try buildRequest(body: body)
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)

        switch ResponseNormalizer.normalizeGroupScoreResponse(data, apiProtocol: apiProtocol) {
        case .success(let result): return result
        case .failure(let error): throw ProviderHTTPSupport.wrapNormalizerError(error)
        }
    }

    func detailedAnalysis(image: ProviderImagePayload, context: PhotoContext) async throws -> DetailedAnalysisResult {
        let prompt = PromptBuilder.detailedAnalysisPrompt(context)
        let body = try buildRequestBody(systemPrompt: prompt.system, userPrompt: prompt.user, images: [image])
        let request = try buildRequest(body: body)
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)

        switch ResponseNormalizer.normalizeDetailedAnalysisResponse(data, apiProtocol: apiProtocol) {
        case .success(let result): return result
        case .failure(let error): throw ProviderHTTPSupport.wrapNormalizerError(error)
        }
    }

    func testConnection() async throws -> Bool {
        // 用最小 payload（一句 ping）测试 endpoint + key 是否可达。
        let body: [String: Any] = [
            "contents": [["parts": [["text": "ping"]]]],
            "generationConfig": ["maxOutputTokens": 1]
        ]
        let request = try buildRequest(body: try JSONSerialization.data(withJSONObject: body))
        let (data, response) = try await httpClient.send(request)
        try ProviderHTTPSupport.ensureSuccess(response, body: data)
        return true
    }

    // MARK: - Request 构造

    func buildRequest(body: Data) throws -> URLRequest {
        let base = try ProviderHTTPSupport.parseEndpoint(endpoint)
            .appendingPathComponent("v1beta/models/\(modelID):generateContent")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw LumaError.networkFailed("Gemini: 无法构造 URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    func buildRequestBody(systemPrompt: String, userPrompt: String, images: [ProviderImagePayload]) throws -> Data {
        // Gemini 没有独立 system role；将 system + user 合并成同一个 user message。
        var parts: [[String: Any]] = []
        parts.append(["text": systemPrompt + "\n\n" + userPrompt])
        for image in images {
            parts.append([
                "inline_data": [
                    "mime_type": image.mimeType,
                    "data": image.base64
                ]
            ])
        }
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.2
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

}
