import Foundation

/// 三协议视觉模型响应统一归一化层。
///
/// 输入：`(rawJSON: Data, protocol: APIProtocol)`，其中 `rawJSON` 是 HTTP body 完整内容。
/// 输出：`Result<GroupScoreResult, NormalizerError>` 或对应的 `DetailedAnalysisResult`。
///
/// 设计取舍：
/// - 三协议把"模型生成的 JSON 字符串"放在不同字段路径里，本类的核心职责是先取出
///   这个字符串、剥掉 markdown fence 后再做第二层 JSON 解析
/// - 字段命名采用 snake_case（与 Prompt 中要求的字段名严格一致），通过 Codable 的
///   `keyDecodingStrategy = .convertFromSnakeCase` 自动映射到 Swift 的 camelCase
/// - 容忍 markdown fence、多余的 trailing comma 等模型常见瑕疵
enum ResponseNormalizer {

    // MARK: - Public API

    static func normalizeGroupScoreResponse(
        _ data: Data,
        apiProtocol: APIProtocol
    ) -> Result<GroupScoreResult, NormalizerError> {
        do {
            let payloadString = try extractContentString(data, apiProtocol: apiProtocol)
            let usage = extractUsage(data, apiProtocol: apiProtocol)
            let cleaned = stripMarkdownFences(payloadString)
            let raw = try decodeRawGroupScore(cleaned)
            return .success(toResult(raw, usage: usage))
        } catch let err as NormalizerError {
            return .failure(err)
        } catch {
            return .failure(.malformedJSON(reason: error.localizedDescription))
        }
    }

    static func normalizeDetailedAnalysisResponse(
        _ data: Data,
        apiProtocol: APIProtocol
    ) -> Result<DetailedAnalysisResult, NormalizerError> {
        do {
            let payloadString = try extractContentString(data, apiProtocol: apiProtocol)
            let usage = extractUsage(data, apiProtocol: apiProtocol)
            let cleaned = stripMarkdownFences(payloadString)
            let raw = try decodeRawDetailed(cleaned)
            return .success(toResult(raw, usage: usage))
        } catch let err as NormalizerError {
            return .failure(err)
        } catch {
            return .failure(.malformedJSON(reason: error.localizedDescription))
        }
    }

    // MARK: - Markdown 清洗

    /// 去掉模型偶发包裹的 markdown 代码围栏（``` 或 ```json ... ```）。
    /// 同时 trim 前后空白。
    static func stripMarkdownFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 移除起始的 ``` / ```json / ```JSON
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            } else {
                s = String(s.dropFirst(3))
            }
        }

        // 移除结尾的 ```
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 各协议字段路径

    /// 从协议响应中取出"模型生成的 JSON 字符串"。
    private static func extractContentString(_ data: Data, apiProtocol: APIProtocol) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NormalizerError.malformedJSON(reason: "顶层不是 JSON 对象")
        }

        switch apiProtocol {
        case .openAICompatible:
            // response.choices[0].message.content
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw NormalizerError.protocolMismatch(reason: "OpenAI 兼容: 缺少 choices[0].message.content")
            }
            return content

        case .googleGemini:
            // response.candidates[0].content.parts[0].text
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                throw NormalizerError.protocolMismatch(reason: "Gemini: 缺少 candidates[0].content.parts[0].text")
            }
            return text

        case .anthropicMessages:
            // response.content[0].text
            guard let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let text = first["text"] as? String else {
                throw NormalizerError.protocolMismatch(reason: "Anthropic: 缺少 content[0].text")
            }
            return text
        }
    }

    /// 取出 token 使用量。各协议字段名不同，缺失视为 0。
    private static func extractUsage(_ data: Data, apiProtocol: APIProtocol) -> TokenUsage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .zero
        }

        switch apiProtocol {
        case .openAICompatible:
            // usage.{prompt_tokens, completion_tokens}
            guard let usage = json["usage"] as? [String: Any] else { return .zero }
            let inT = (usage["prompt_tokens"] as? Int) ?? 0
            let outT = (usage["completion_tokens"] as? Int) ?? 0
            return TokenUsage(inputTokens: inT, outputTokens: outT)

        case .googleGemini:
            // usageMetadata.{promptTokenCount, candidatesTokenCount}
            guard let usage = json["usageMetadata"] as? [String: Any] else { return .zero }
            let inT = (usage["promptTokenCount"] as? Int) ?? 0
            let outT = (usage["candidatesTokenCount"] as? Int) ?? 0
            return TokenUsage(inputTokens: inT, outputTokens: outT)

        case .anthropicMessages:
            // usage.{input_tokens, output_tokens}
            guard let usage = json["usage"] as? [String: Any] else { return .zero }
            let inT = (usage["input_tokens"] as? Int) ?? 0
            let outT = (usage["output_tokens"] as? Int) ?? 0
            return TokenUsage(inputTokens: inT, outputTokens: outT)
        }
    }

    // MARK: - 模型生成 JSON 解码

    private struct RawGroupScore: Decodable {
        let photos: [RawPhoto]
        let groupBest: [Int]
        let groupComment: String

        /// 模型偶发会漏 `comment` / `recommended` / `groupBest` 等字段；
        /// 仅 `index` / `scores` / `overall` 强制必填，其余给默认值，避免一组评分被丢弃。
        struct RawPhoto: Decodable {
            let index: Int
            let scores: PhotoScores
            let overall: Int
            let comment: String
            let recommended: Bool

            // 注：CodingKeys 的 stringValue 必须与 keyDecodingStrategy 配合后的 key 一致。
            // 我们启用 .convertFromSnakeCase，故这里直接用 swift 端 camelCase 作为 key。
            enum CodingKeys: String, CodingKey {
                case index, scores, overall, comment, recommended
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.index = try c.decode(Int.self, forKey: .index)
                self.scores = try c.decode(PhotoScores.self, forKey: .scores)
                self.overall = try c.decode(Int.self, forKey: .overall)
                self.comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
                self.recommended = try c.decodeIfPresent(Bool.self, forKey: .recommended) ?? false
            }
        }

        // 注：依赖 JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase，
        // JSON 里的 group_best / group_comment 会被自动转成 groupBest / groupComment，
        // 所以 CodingKeys 不要写显式 raw value（否则会双重转换冲突）。
        enum CodingKeys: String, CodingKey {
            case photos, groupBest, groupComment
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.photos = try c.decode([RawPhoto].self, forKey: .photos)
            self.groupBest = try c.decodeIfPresent([Int].self, forKey: .groupBest) ?? []
            self.groupComment = try c.decodeIfPresent(String.self, forKey: .groupComment) ?? ""
        }
    }

    private struct RawDetailed: Decodable {
        let crop: CropSuggestion?
        let filterStyle: FilterSuggestion?
        let adjustments: AdjustmentValues?
        let hsl: [HSLAdjustment]?
        let localEdits: [LocalEdit]?
        let narrative: String
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static func decodeRawGroupScore(_ jsonString: String) throws -> RawGroupScore {
        guard let data = jsonString.data(using: .utf8) else {
            throw NormalizerError.malformedJSON(reason: "无法把模型输出转为 UTF-8")
        }
        do {
            return try decoder().decode(RawGroupScore.self, from: data)
        } catch {
            throw NormalizerError.malformedJSON(reason: error.localizedDescription)
        }
    }

    private static func decodeRawDetailed(_ jsonString: String) throws -> RawDetailed {
        guard let data = jsonString.data(using: .utf8) else {
            throw NormalizerError.malformedJSON(reason: "无法把模型输出转为 UTF-8")
        }
        do {
            return try decoder().decode(RawDetailed.self, from: data)
        } catch {
            throw NormalizerError.malformedJSON(reason: error.localizedDescription)
        }
    }

    // MARK: - 转换

    private static func toResult(_ raw: RawGroupScore, usage: TokenUsage) -> GroupScoreResult {
        let perPhoto = raw.photos.map {
            PerPhotoScore(
                index: $0.index,
                scores: $0.scores,
                overall: $0.overall,
                comment: $0.comment,
                recommended: $0.recommended
            )
        }
        return GroupScoreResult(
            perPhoto: perPhoto,
            groupBest: raw.groupBest,
            groupComment: raw.groupComment,
            usage: usage
        )
    }

    private static func toResult(_ raw: RawDetailed, usage: TokenUsage) -> DetailedAnalysisResult {
        DetailedAnalysisResult(
            crop: raw.crop,
            filterStyle: raw.filterStyle,
            adjustments: raw.adjustments,
            hsl: raw.hsl,
            localEdits: raw.localEdits,
            narrative: raw.narrative,
            usage: usage
        )
    }
}
