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
        let description = xmlEscaped(asset.aiScore?.comment ?? "")
        let subject = xmlEscaped(group?.name ?? "")
        let keywords = xmlEscaped(group?.name ?? "")
        let adjustments = includeEditSuggestions ? adjustmentFragment(for: asset.editSuggestions) : ""

        return """
        <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
              xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
              xmp:Rating="\(rating)"
              xmp:Label="\(label)"
              dc:description="\(description)"
              dc:subject="\(keywords)"
              lr:hierarchicalSubject="\(subject)">
              \(adjustments)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

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

    private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

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
