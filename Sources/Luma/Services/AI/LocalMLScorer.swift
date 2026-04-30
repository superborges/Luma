import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

struct LocalMLAssessment: Codable, Hashable {
    let issues: [AssetIssue]
    let score: Int
    let subscores: PhotoScores
    let comment: String
    let recommended: Bool
}

struct LocalMLScorer: Sendable {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func score(asset: MediaAsset) async -> LocalMLAssessment {
        guard let sourceURL = asset.previewURL ?? asset.rawURL else {
            return LocalMLAssessment(
                issues: [.unsupportedFormat],
                score: 15,
                subscores: PhotoScores(composition: 35, exposure: 20, color: 20, sharpness: 10, story: 35),
                comment: "素材无法读取，建议跳过或手动检查。",
                recommended: false
            )
        }

        return await Task.detached(priority: .utility) {
            Self.analyzeAsset(from: sourceURL)
        }.value
    }

    private static func analyzeAsset(from sourceURL: URL) -> LocalMLAssessment {
        guard let cgImage = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 512) else {
            return LocalMLAssessment(
                issues: [.unsupportedFormat],
                score: 15,
                subscores: PhotoScores(composition: 35, exposure: 20, color: 20, sharpness: 10, story: 35),
                comment: "素材无法生成预览，建议跳过或手动检查。",
                recommended: false
            )
        }

        let image = CIImage(cgImage: cgImage)
        let brightness = averageLuminance(of: image)
        let edgeStrength = edgeStrength(of: image)
        let colorfulness = colorfulness(of: image)
        let faceQuality = detectFaceQuality(in: cgImage)

        var issues: [AssetIssue] = []
        if edgeStrength < 0.09 {
            issues.append(.blurry)
        }
        if brightness > 0.84 {
            issues.append(.overexposed)
        }
        if brightness < 0.18 {
            issues.append(.underexposed)
        }
        if let faceQuality, faceQuality > 0, faceQuality < 0.15 {
            issues.append(.eyesClosed)
        }

        let sharpness = clamp(Int(edgeStrength * 700), lower: 20, upper: 96)
        let exposureScore = clamp(Int((1 - abs(brightness - 0.5) * 2) * 100), lower: 18, upper: 96)
        let colorScore = clamp(Int(colorfulness * 260), lower: 25, upper: 92)
        let composition = clamp(Int(Double(sharpness + exposureScore) * 0.45), lower: 35, upper: 88)
        let story = clamp(Int(Double(colorScore + exposureScore) * 0.42), lower: 35, upper: 86)

        var overall = Int(
            Double(composition) * 0.18 +
            Double(exposureScore) * 0.26 +
            Double(colorScore) * 0.16 +
            Double(sharpness) * 0.28 +
            Double(story) * 0.12
        )

        if issues.contains(.blurry) { overall -= 34 }
        if issues.contains(.overexposed) { overall -= 20 }
        if issues.contains(.underexposed) { overall -= 18 }
        if issues.contains(.eyesClosed) { overall -= 14 }
        overall = clamp(overall, lower: issues.isEmpty ? 45 : 8, upper: 96)

        let comment: String
        if issues.isEmpty {
            if overall >= 75 {
                comment = "技术质量稳定，可进入下一轮精选。"
            } else {
                comment = "成片基础可靠，但建议结合组内比较再决定。"
            }
        } else {
            comment = issues.map(\.label).joined(separator: "、") + "，建议优先淘汰或仅作备份。"
        }

        let subscores = PhotoScores(
            composition: composition,
            exposure: exposureScore,
            color: colorScore,
            sharpness: sharpness,
            story: story
        )

        return LocalMLAssessment(
            issues: issues,
            score: overall,
            subscores: subscores,
            comment: comment,
            recommended: issues.isEmpty && overall >= 72
        )
    }

    private static func averageLuminance(of image: CIImage) -> Double {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return 0.5 }
        guard let rgba = renderedRGBA(from: output) else { return 0.5 }
        return 0.2126 * rgba.0 + 0.7152 * rgba.1 + 0.0722 * rgba.2
    }

    private static func edgeStrength(of image: CIImage) -> Double {
        let filter = CIFilter.edges()
        filter.inputImage = image
        filter.intensity = 8
        guard let output = filter.outputImage else { return 0.1 }
        let luminance = averageLuminance(of: output)
        return clamp(luminance, lower: 0.01, upper: 0.25)
    }

    private static func colorfulness(of image: CIImage) -> Double {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage,
              let rgba = renderedRGBA(from: output) else { return 0.3 }
        let maxChannel = max(rgba.0, max(rgba.1, rgba.2))
        let minChannel = min(rgba.0, min(rgba.1, rgba.2))
        return maxChannel - minChannel
    }

    private static func renderedRGBA(from image: CIImage) -> (Double, Double, Double, Double)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        ciContext.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return (
            Double(pixel[0]) / 255.0,
            Double(pixel[1]) / 255.0,
            Double(pixel[2]) / 255.0,
            Double(pixel[3]) / 255.0
        )
    }

    private static func detectFaceQuality(in image: CGImage) -> Double? {
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([qualityRequest])
            guard let observations = qualityRequest.results, !observations.isEmpty else {
                return nil
            }
            let qualities = observations.compactMap(\.faceCaptureQuality).map(Double.init)
            return qualities.min()
        } catch {
            return nil
        }
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
