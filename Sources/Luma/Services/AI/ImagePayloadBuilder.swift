import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把 `MediaAsset` / `URL` / `CGImage` 转换为 `ProviderImagePayload`（长边 1024px、JPEG 85%、base64）。
///
/// 设计取舍：
/// - 选用 1024px 长边 + 85% 质量是经验值，能在多模态模型中保留构图与色彩信息，
///   同时把每张图压到 80-150KB（base64 后 ~110-200KB），明显降低 token 开销
/// - 全部跑在 background queue，不阻塞主 actor
/// - 调用方负责保证传入的 URL 已落盘可读；本类只做"图像到 base64"的转换
enum ImagePayloadBuilder {
    static let targetLongEdge = 1024
    static let jpegCompressionQuality: Double = 0.85

    /// 从图像文件构造 payload。失败返回 nil（调用方决定是否跳过该图）。
    static func payload(from sourceURL: URL) async -> ProviderImagePayload? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: makePayloadSync(from: sourceURL))
            }
        }
    }

    /// 从已解码的 CGImage 构造 payload（用于已经在内存的缩略图）。
    static func payload(from cgImage: CGImage) async -> ProviderImagePayload? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: makePayloadSync(from: cgImage))
            }
        }
    }

    // MARK: - 内部同步实现

    private static func makePayloadSync(from sourceURL: URL) -> ProviderImagePayload? {
        guard let cg = EXIFParser.cgImageForDisplay(at: sourceURL, maxLongEdge: targetLongEdge) else {
            return nil
        }
        return makePayloadSync(from: cg)
    }

    private static func makePayloadSync(from cgImage: CGImage) -> ProviderImagePayload? {
        let resized = resizeIfNeeded(cgImage)
        guard let jpegData = encodeJPEG(resized, quality: jpegCompressionQuality) else {
            return nil
        }
        let base64 = jpegData.base64EncodedString()
        let longEdge = max(resized.width, resized.height)
        return ProviderImagePayload(base64: base64, longEdgePixels: longEdge, mimeType: ProviderImagePayload.defaultMimeType)
    }

    /// 把 CGImage 长边降采样到 ≤ targetLongEdge。若已 ≤ 目标值则直接返回原图。
    private static func resizeIfNeeded(_ image: CGImage) -> CGImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > targetLongEdge else { return image }

        let scale = Double(targetLongEdge) / Double(longEdge)
        let targetWidth = Int(Double(image.width) * scale)
        let targetHeight = Int(Double(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }

    /// 用 ImageIO 编码 JPEG。失败返回 nil。
    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        return mutableData as Data
    }
}
