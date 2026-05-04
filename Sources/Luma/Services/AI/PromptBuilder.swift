import Foundation

/// 视觉模型 Prompt 构造器。两套模板写死，不开放运行时自定义。
///
/// 设计取舍：
/// - System 强制 JSON-only 输出，避免 markdown / preamble 污染
/// - 中文输出（评语 / narrative）由 System 强约束
/// - 字段名与 `GroupScoreResult` / `DetailedAnalysisResult` 严格对齐，方便 Normalizer 直接 Codable
enum PromptBuilder {

    // MARK: - Group scoring

    /// 组内批量评分 Prompt。`photoCount` 用于在 user 文本中占位，使模型知道图像数量。
    ///
    /// **方案 A：评分锚点（anchoring）**——给模型显式分布提示，缓解 LLM 默认的"评分膨胀"
    /// （leniency bias）。详见 `docs/V2/AI Scoring Workflow.md` § 10。
    static func groupScoringPrompt(_ context: GroupContext, photoCount: Int) -> (system: String, user: String) {
        let system = """
        You are a STRICT and CRITICAL photo editor doing first-pass culling for a serious photographer.
        Your job is to RANK and FILTER, not to give polite encouragement.

        Score each photo on each dimension from 0 to 100. Use the FULL range — most photos
        in a typical amateur photoshoot are NOT 80+. Be honest and discriminating.

        SCORE DISTRIBUTION ANCHORS (very important — calibrate to these):
        - 90-100: Award-winning. Exceptional in nearly every dimension. Roughly TOP 3-5%
                  of a casual photoshoot. Reserve this for genuinely portfolio-worthy frames.
        - 75-89:  Good. Sharp, well-composed, emotionally engaging. Worth keeping. ~20-30%.
        - 60-74:  Acceptable but flawed. Minor blur / weak composition / dull color / mediocre subject.
                  Most snapshots fall here.
        - 40-59:  Mediocre. Significant problems (out of focus, bad framing, washed out).
                  Likely to be rejected after careful review.
        - 0-39:   Reject. Unusable due to severe blur / closed eyes / heavy overexposure / camera shake.

        CALIBRATION RULES:
        - Be a strict gatekeeper, NOT a cheerleader. If a photo has obvious flaws, score it accordingly.
        - For a group of similar photos taken at the same scene, scores should DIFFER by at least 5-10
          points between the best and worst — show your judgment of relative quality.
        - DO NOT cluster all scores in 70-85. Use 50s and 60s freely when warranted.
        - "recommended: true" should apply to AT MOST 1-2 photos per group of 5+, even fewer
          if the group is uniformly mediocre.

        OUTPUT FORMAT:
        - Respond ONLY in JSON. No markdown fences, no preamble, no trailing text.
        - All comment / group_comment text must be in Chinese (简体中文).
        - The Chinese comment should be honest — point out specific flaws, not generic praise.
        """

        var lines: [String] = []
        lines.append("Here are \(photoCount) photos from scene: \"\(context.groupName)\".")
        var meta: [String] = []
        if let camera = context.cameraModel { meta.append("Camera: \(camera)") }
        if let lens = context.lensModel { meta.append("Lens: \(lens)") }
        if let range = context.timeRangeDescription { meta.append("Time range: \(range)") }
        if !meta.isEmpty {
            lines.append(meta.joined(separator: " | "))
        }
        lines.append("")
        lines.append("Return JSON:")
        lines.append("""
        {
          "photos": [
            {
              "index": 1,
              "scores": {
                "composition": 0-100,
                "exposure": 0-100,
                "color": 0-100,
                "sharpness": 0-100,
                "story": 0-100
              },
              "overall": 0-100,
              "comment": "一句话中文评价",
              "recommended": true
            }
          ],
          "group_best": [1, 5],
          "group_comment": "整组中文点评"
        }
        """)
        lines.append("")
        lines.append("Index starts from 1 and matches the order of attached images.")

        return (system, lines.joined(separator: "\n"))
    }

    // MARK: - Group naming

    /// AI 组名生成 Prompt。要求返回纯文本（非 JSON），≤ 8 个汉字。
    static func groupNamingPrompt(currentName: String, location: String?, photoCount: Int) -> (system: String, user: String) {
        let system = """
        你是一位专业摄影师的照片管理助手。根据照片内容，为这组照片生成一个简短的描述性名称。
        规则：
        - 仅返回名称文本，不要返回 JSON、不要加引号、不要有任何多余文字
        - 名称 ≤ 8 个汉字
        - 格式：「地点·场景」或「主题·氛围」
        - 如果照片包含明显的地标或场景，用地点名
        - 如果照片是某个活动或主题，用主题描述
        - 简洁有力，避免泛泛之词如「日常」「随拍」
        """

        var lines: [String] = []
        lines.append("这组照片共 \(photoCount) 张，当前名称：「\(currentName)」。")
        if let loc = location {
            lines.append("拍摄位置：\(loc)")
        }
        lines.append("请根据照片内容生成一个更好的描述性名称。")

        return (system, lines.joined(separator: "\n"))
    }

    // MARK: - Detailed analysis

    /// 单张精评 + 修图建议 Prompt。
    static func detailedAnalysisPrompt(_ context: PhotoContext) -> (system: String, user: String) {
        let system = """
        You are a master photographer and retouching expert. Analyze this photo
        and provide detailed editing suggestions with specific values.
        Respond ONLY in JSON format. No markdown fences, no preamble.
        All text fields (direction, mood, area, action, narrative) must be in Chinese (简体中文).
        """

        var meta: [String] = []
        if let aperture = context.exif.aperture { meta.append(String(format: "f/%.1f", aperture)) }
        if let shutter = context.exif.shutterSpeed { meta.append(shutter) }
        if let iso = context.exif.iso { meta.append("ISO \(iso)") }
        if let focal = context.exif.focalLength { meta.append(String(format: "%.0fmm", focal)) }
        let exifLine = meta.isEmpty ? "EXIF: -" : "EXIF: " + meta.joined(separator: ", ")

        let scoreLine: String
        if let initial = context.initialOverallScore {
            scoreLine = "Scene: \(context.groupName) | Initial score: \(initial)/100"
        } else {
            scoreLine = "Scene: \(context.groupName)"
        }

        let user = """
        Photo: \(context.baseName) | \(exifLine)
        \(scoreLine)

        Return JSON:
        {
          "crop": {
            "needed": true,
            "ratio": "16:9",
            "direction": "裁切方向描述（中文）",
            "rule": "rule_of_thirds | golden_ratio | center | leading_lines",
            "top": 0.0,
            "bottom": 1.0,
            "left": 0.0,
            "right": 1.0,
            "angle": 0.0
          },
          "filter_style": {
            "primary": "warm_golden_hour | cool_cinematic | moody_dark | clean_minimal | vintage_film",
            "reference": "具体参考滤镜名（如 VSCO A6、Fuji Velvia）",
            "mood": "氛围描述（中文）"
          },
          "adjustments": {
            "exposure": -3.0,
            "contrast": -100,
            "highlights": -100,
            "shadows": -100,
            "temperature": -2000,
            "tint": -100,
            "saturation": -100,
            "vibrance": -100,
            "clarity": -100,
            "dehaze": -100
          },
          "hsl": [
            {"color": "orange", "hue": -20, "saturation": -100, "luminance": -100}
          ],
          "local_edits": [
            {"area": "区域名（中文）", "action": "具体操作描述（中文）"}
          ],
          "narrative": "完整修图思路，2-3 句中文"
        }
        """

        return (system, user)
    }
}
