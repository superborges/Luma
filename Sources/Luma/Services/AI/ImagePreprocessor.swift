import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImagePreprocessor {
    static func prepareImage(from url: URL, maxPixelSize: Int = 1024, quality: Double = 0.85) throws -> ImageData {
        guard let cgImage = EXIFParser.makeThumbnail(from: url, maxPixelSize: maxPixelSize) else {
            throw LumaError.unsupported("Unable to prepare image: \(url.lastPathComponent)")
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LumaError.unsupported("Unable to encode JPEG data.")
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LumaError.unsupported("Unable to finalize JPEG data.")
        }

        return ImageData(
            filename: url.lastPathComponent,
            mimeType: "image/jpeg",
            data: mutableData as Data
        )
    }

    static func makeConnectionTestImage(size: Int = 256) throws -> ImageData {
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                pixels[offset] = UInt8((Double(x) / Double(size)) * 255)
                pixels[offset + 1] = UInt8((Double(y) / Double(size)) * 255)
                pixels[offset + 2] = 180
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage() else {
            throw LumaError.unsupported("Unable to create connection test image.")
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LumaError.unsupported("Unable to encode connection test image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LumaError.unsupported("Unable to finalize connection test image.")
        }

        return ImageData(filename: "connection-test.jpg", mimeType: "image/jpeg", data: mutableData as Data)
    }

    static func estimatedInputTokens(for images: [ImageData]) -> Int {
        images.reduce(0) { total, image in
            total + max(1, image.data.count / 750)
        }
    }
}
