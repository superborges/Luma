import Foundation

enum AIPromptBuilder {
    static func groupPrompt(imagesCount: Int, context: GroupContext) -> (system: String, user: String) {
        let system = """
        You are a professional photo editor evaluating a group of similar photos taken at the same scene.
        Score each photo and recommend the best ones.
        Respond ONLY in JSON format. No markdown fences, no preamble.
        All comments must be in Chinese (简体中文).
        """

        let user = """
        Here are \(imagesCount) photos from scene: "\(context.groupName)".
        Camera: \(context.cameraModel ?? "Unknown") | Lens: \(context.lensModel ?? "Unknown") | Time range: \(context.timeRangeDescription)

        Return JSON:
        {
          "photos": [
            {
              "index": 1,
              "scores": {
                "composition": 0,
                "exposure": 0,
                "color": 0,
                "sharpness": 0,
                "story": 0
              },
              "overall": 0,
              "comment": "一句话中文评价",
              "recommended": true
            }
          ],
          "group_best": [1],
          "group_comment": "整组中文点评"
        }
        """

        return (system, user)
    }

    static func detailedPrompt(context: PhotoContext) -> (system: String, user: String) {
        let system = """
        You are a master photographer and retouching expert.
        Analyze this photo and provide detailed editing suggestions with specific values.
        Respond ONLY in JSON format. No markdown fences, no preamble.
        All text fields must be in Chinese (简体中文).
        """

        let user = """
        EXIF: \(context.exifSummary)
        Scene: \(context.groupName) | Initial score: \(context.initialScore.map(String.init) ?? "Unknown")/100

        Return JSON:
        {
          "crop": {
            "needed": true,
            "ratio": "4:5",
            "direction": "裁切方向描述",
            "rule": "rule_of_thirds",
            "top": 0.0,
            "bottom": 1.0,
            "left": 0.0,
            "right": 1.0
          },
          "filter_style": {
            "primary": "clean_minimal",
            "reference": "参考滤镜",
            "mood": "氛围描述"
          },
          "adjustments": {
            "exposure": 0.0,
            "contrast": 0,
            "highlights": 0,
            "shadows": 0,
            "temperature": 0,
            "tint": 0,
            "saturation": 0,
            "vibrance": 0,
            "clarity": 0,
            "dehaze": 0
          },
          "hsl": [
            {"color": "orange", "hue": 0, "saturation": 0, "lum": 0}
          ],
          "local_edits": [
            {"area": "区域名", "action": "具体操作描述"}
          ],
          "narrative": "完整修图思路，2-3句话"
        }
        """

        return (system, user)
    }
}
