import Foundation

enum ResponseNormalizer {
    static func sanitizeJSONEnvelope(_ rawText: String) -> String {
        rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode<T: Decodable>(_ type: T.Type, from rawText: String) throws -> T {
        let sanitized = sanitizeJSONEnvelope(rawText)
        let decoder = JSONDecoder.lumaDecoder
        return try decoder.decode(T.self, from: Data(sanitized.utf8))
    }

    static func parseGroupScore(provider: String, rawText: String) throws -> GroupScoreResult {
        let decoded = try decode(GroupScoreEnvelope.self, from: rawText)
        return GroupScoreResult(
            photoResults: decoded.photos.map { photo in
                ScoredPhotoResult(
                    index: photo.index,
                    score: AIScore(
                        provider: provider,
                        scores: PhotoScores(
                            composition: photo.scores.composition,
                            exposure: photo.scores.exposure,
                            color: photo.scores.color,
                            sharpness: photo.scores.sharpness,
                            story: photo.scores.story
                        ),
                        overall: photo.overall,
                        comment: photo.comment,
                        recommended: photo.recommended,
                        timestamp: .now
                    )
                )
            },
            groupBest: decoded.groupBest ?? [],
            groupComment: decoded.groupComment,
            usage: nil
        )
    }

    static func parseDetailedAnalysis(rawText: String) throws -> DetailedAnalysisResult {
        let decoded = try decode(DetailedAnalysisEnvelope.self, from: rawText)
        return DetailedAnalysisResult(
            suggestions: EditSuggestions(
                crop: decoded.crop.map {
                    CropSuggestion(
                        needed: $0.needed,
                        ratio: $0.ratio ?? "4:5",
                        direction: $0.direction ?? "",
                        rule: $0.rule ?? "rule_of_thirds",
                        top: $0.top,
                        bottom: $0.bottom,
                        left: $0.left,
                        right: $0.right,
                        angle: $0.angle
                    )
                },
                filterStyle: decoded.filterStyle.map {
                    FilterSuggestion(
                        primary: $0.primary,
                        reference: $0.reference,
                        mood: $0.mood
                    )
                },
                adjustments: decoded.adjustments.map {
                    AdjustmentValues(
                        exposure: $0.exposure,
                        contrast: $0.contrast,
                        highlights: $0.highlights,
                        shadows: $0.shadows,
                        temperature: $0.temperature,
                        tint: $0.tint,
                        saturation: $0.saturation,
                        vibrance: $0.vibrance,
                        clarity: $0.clarity,
                        dehaze: $0.dehaze
                    )
                },
                hslAdjustments: decoded.hsl?.map {
                    HSLAdjustment(
                        color: $0.color,
                        hue: $0.hue,
                        saturation: $0.saturation,
                        luminance: $0.luminance
                    )
                },
                localEdits: decoded.localEdits?.map {
                    LocalEdit(area: $0.area, action: $0.action)
                },
                narrative: decoded.narrative ?? "未返回修图建议。"
            ),
            rawResponse: sanitizeJSONEnvelope(rawText),
            usage: nil
        )
    }
}

private struct GroupScoreEnvelope: Decodable {
    let photos: [GroupScorePhoto]
    let groupBest: [Int]?
    let groupComment: String?

    enum CodingKeys: String, CodingKey {
        case photos
        case groupBest = "group_best"
        case groupComment = "group_comment"
    }
}

private struct GroupScorePhoto: Decodable {
    let index: Int
    let scores: GroupScoreSubscores
    let overall: Int
    let comment: String
    let recommended: Bool
}

private struct GroupScoreSubscores: Decodable {
    let composition: Int
    let exposure: Int
    let color: Int
    let sharpness: Int
    let story: Int
}

private struct DetailedAnalysisEnvelope: Decodable {
    let crop: CropEnvelope?
    let filterStyle: FilterStyleEnvelope?
    let adjustments: AdjustmentsEnvelope?
    let hsl: [HSLEnvelope]?
    let localEdits: [LocalEditEnvelope]?
    let narrative: String?

    enum CodingKeys: String, CodingKey {
        case crop
        case filterStyle = "filter_style"
        case adjustments
        case hsl
        case localEdits = "local_edits"
        case narrative
    }
}

private struct CropEnvelope: Decodable {
    let needed: Bool
    let ratio: String?
    let direction: String?
    let rule: String?
    let top: Double?
    let bottom: Double?
    let left: Double?
    let right: Double?
    let angle: Double?
}

private struct FilterStyleEnvelope: Decodable {
    let primary: String
    let reference: String
    let mood: String
}

private struct AdjustmentsEnvelope: Decodable {
    let exposure: Double?
    let contrast: Int?
    let highlights: Int?
    let shadows: Int?
    let temperature: Int?
    let tint: Int?
    let saturation: Int?
    let vibrance: Int?
    let clarity: Int?
    let dehaze: Int?
}

private struct HSLEnvelope: Decodable {
    let color: String
    let hue: Int?
    let saturation: Int?
    let luminance: Int?

    enum CodingKeys: String, CodingKey {
        case color
        case hue
        case saturation
        case luminance = "lum"
    }
}

private struct LocalEditEnvelope: Decodable {
    let area: String
    let action: String
}
