import Foundation

enum XMPWriter {
    static func writeSidecar(for asset: MediaAsset, group: PhotoGroup?, nextTo imageURL: URL, includeEditSuggestions: Bool = false) throws {
        let xmpURL = imageURL.deletingPathExtension().appendingPathExtension("xmp")
        try xmp(for: asset, group: group, includeEditSuggestions: includeEditSuggestions).write(to: xmpURL, atomically: true, encoding: .utf8)
    }

    static func xmp(for asset: MediaAsset, group: PhotoGroup?, includeEditSuggestions: Bool = false) -> String {
        let rating = starRating(for: asset)
        let label = switch asset.userDecision {
        case .picked: "Green"
        case .pending: "Yellow"
        case .rejected: "Red"
        }

        let descriptionText = xmlEscaped(composedDescription(for: asset, includeEditSuggestions: includeEditSuggestions))
        let subjectKeywords = buildSubjectKeywords(asset: asset, group: group)
        let hierarchicalSubject = group?.name ?? ""
        let adjustments = includeEditSuggestions ? adjustmentFragment(for: asset.editSuggestions) : ""

        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
              xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
              xmp:Rating="\(rating)"
              xmp:Label="\(label)">
              <dc:description>
                <rdf:Alt>
                  <rdf:li xml:lang="x-default">\(descriptionText)</rdf:li>
                </rdf:Alt>
              </dc:description>
              \(subjectBagXML(subjectKeywords))
              \(hierarchicalSubjectBagXML(hierarchicalSubject))
              \(adjustments)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    // MARK: - Keywords

    private static func buildSubjectKeywords(asset: MediaAsset, group: PhotoGroup?) -> [String] {
        var keywords: [String] = []

        if let groupName = group?.name, !groupName.isEmpty {
            keywords.append(groupName)
        }

        for issue in asset.issues {
            keywords.append(issue.label)
        }

        return keywords
    }

    private static func subjectBagXML(_ keywords: [String]) -> String {
        guard !keywords.isEmpty else { return "<dc:subject><rdf:Bag/></dc:subject>" }
        let items = keywords.map { "<rdf:li>\(xmlEscaped($0))</rdf:li>" }
        let inner = items.map { "                \($0)" }.joined(separator: "\n")
        return "<dc:subject>\n                <rdf:Bag>\n\(inner)\n                </rdf:Bag>\n              </dc:subject>"
    }

    private static func hierarchicalSubjectBagXML(_ subject: String) -> String {
        guard !subject.isEmpty else { return "" }
        return "<lr:hierarchicalSubject>\n                <rdf:Bag>\n                <rdf:li>\(xmlEscaped(subject))</rdf:li>\n                </rdf:Bag>\n              </lr:hierarchicalSubject>"
    }

    // MARK: - Rating

    private static func starRating(for asset: MediaAsset) -> Int {
        if let userRating = asset.userRating {
            return min(max(userRating, 1), 5)
        }

        let overall = asset.aiScore?.overall ?? 0
        switch overall {
        case 90...:
            return 5
        case 75..<90:
            return 4
        case 60..<75:
            return 3
        case 45..<60:
            return 2
        default:
            return 1
        }
    }

    // MARK: - Description（评分评语 + 修图建议文字）

    /// `dc:description`：始终包含 AI 评分评语；勾选「写入修图建议」时追加 narrative / 风格 / HSL / 局部说明（Lightroom 可读作说明字段）。
    private static func composedDescription(for asset: MediaAsset, includeEditSuggestions: Bool) -> String {
        var sections: [String] = []
        if let score = asset.aiScore {
            let comment = score.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !comment.isEmpty { sections.append(comment) }
        }
        guard includeEditSuggestions, let s = asset.editSuggestions else {
            return sections.joined(separator: "\n\n")
        }

        let narr = s.narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        if !narr.isEmpty {
            sections.append(narr)
        }

        if let fs = s.filterStyle {
            let bits = [fs.primary, fs.reference, fs.mood].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !bits.isEmpty {
                sections.append("风格参考：" + bits.joined(separator: " · "))
            }
        }

        if let hsl = s.hslAdjustments, !hsl.isEmpty {
            let lines = hsl.map { h -> String in
                var parts: [String] = [h.color]
                if let hue = h.hue { parts.append("色相 \(hue)") }
                if let sat = h.saturation { parts.append("饱和 \(sat)") }
                if let lum = h.luminance { parts.append("明亮 \(lum)") }
                return parts.joined(separator: " ")
            }
            sections.append("HSL 建议：\n" + lines.joined(separator: "\n"))
        }

        if let locals = s.localEdits, !locals.isEmpty {
            let lines = locals.map { "\($0.area)：\($0.action)" }
            sections.append("局部调整：\n" + lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Escaping

    private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - MasterAsset Overload

    static func writeSidecar(
        for asset: MasterAsset,
        groupName: String?,
        rating: Int,
        nextTo imageURL: URL
    ) throws {
        let xmpURL = imageURL.deletingPathExtension().appendingPathExtension("xmp")
        try xmpForMasterAsset(asset, groupName: groupName, rating: rating)
            .write(to: xmpURL, atomically: true, encoding: .utf8)
    }

    static func xmpForMasterAsset(_ asset: MasterAsset, groupName: String?, rating: Int) -> String {
        let label = "Green"
        var keywords: [String] = []
        if let gn = groupName, !gn.isEmpty { keywords.append(gn) }
        let hierarchical = groupName ?? ""

        var descParts: [String] = []
        if let meta = asset.metadata {
            if let cam = meta.cameraModel { descParts.append("Camera: \(cam)") }
            if let lens = meta.lensModel { descParts.append("Lens: \(lens)") }
        }
        let description = xmlEscaped(descParts.joined(separator: " · "))

        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
              xmp:Rating="\(rating)"
              xmp:Label="\(label)">
              <dc:description>
                <rdf:Alt>
                  <rdf:li xml:lang="x-default">\(description)</rdf:li>
                </rdf:Alt>
              </dc:description>
              \(subjectBagXML(keywords))
              \(hierarchicalSubjectBagXML(hierarchical))
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    // MARK: - Edit Suggestions

    private static func adjustmentFragment(for suggestions: EditSuggestions?) -> String {
        guard let suggestions else { return "" }

        var fragments: [String] = []
        if let adjustments = suggestions.adjustments {
            if let exposure = adjustments.exposure {
                fragments.append("<crs:Exposure2012>\(String(format: "%.2f", exposure))</crs:Exposure2012>")
            }
            if let contrast = adjustments.contrast {
                fragments.append("<crs:Contrast2012>\(contrast)</crs:Contrast2012>")
            }
            if let highlights = adjustments.highlights {
                fragments.append("<crs:Highlights2012>\(highlights)</crs:Highlights2012>")
            }
            if let shadows = adjustments.shadows {
                fragments.append("<crs:Shadows2012>\(shadows)</crs:Shadows2012>")
            }
            if let temperature = adjustments.temperature {
                fragments.append("<crs:Temperature>\(5500 + temperature)</crs:Temperature>")
            }
            if let saturation = adjustments.saturation {
                fragments.append("<crs:Saturation>\(saturation)</crs:Saturation>")
            }
            if let vibrance = adjustments.vibrance {
                fragments.append("<crs:Vibrance>\(vibrance)</crs:Vibrance>")
            }
            if let clarity = adjustments.clarity {
                fragments.append("<crs:Clarity2012>\(clarity)</crs:Clarity2012>")
            }
            if let dehaze = adjustments.dehaze {
                fragments.append("<crs:Dehaze>\(dehaze)</crs:Dehaze>")
            }
            if let tint = adjustments.tint {
                fragments.append("<crs:Tint>\(tint)</crs:Tint>")
            }
        }

        if let crop = suggestions.crop, crop.needed {
            fragments.append("<crs:HasCrop>True</crs:HasCrop>")
            if let top = crop.top {
                fragments.append("<crs:CropTop>\(top)</crs:CropTop>")
            }
            if let bottom = crop.bottom {
                fragments.append("<crs:CropBottom>\(bottom)</crs:CropBottom>")
            }
            if let left = crop.left {
                fragments.append("<crs:CropLeft>\(left)</crs:CropLeft>")
            }
            if let right = crop.right {
                fragments.append("<crs:CropRight>\(right)</crs:CropRight>")
            }
            if let angle = crop.angle {
                fragments.append("<crs:CropAngle>\(angle)</crs:CropAngle>")
            }
        }

        return fragments.joined(separator: "\n              ")
    }
}
