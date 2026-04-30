import Foundation
import ImageIO

enum EXIFParser {
    static func parse(from url: URL) -> EXIFData {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return fallbackMetadata(for: url)
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        return EXIFData(
            captureDate: parseDate(exif: exif, tiff: tiff) ?? fileCreationDate(for: url),
            gpsCoordinate: parseCoordinate(gps),
            focalLength: numericValue(exif?[kCGImagePropertyExifFocalLength]),
            aperture: numericValue(exif?[kCGImagePropertyExifFNumber]),
            shutterSpeed: parseShutterSpeed(exif),
            iso: parseISO(exif),
            cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif?[kCGImagePropertyExifLensModel] as? String,
            imageWidth: Int(properties[kCGImagePropertyPixelWidth] as? Double ?? 0),
            imageHeight: Int(properties[kCGImagePropertyPixelHeight] as? Double ?? 0)
        )
    }

    static func makeThumbnail(from url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return decodeThumbnail(source: source, maxPixelSize: maxPixelSize)
    }

    /// 中央大图用：从文件解码到 `maxLongEdge` 尺寸内，保证方向正确。
    static func cgImageForDisplay(at url: URL, maxLongEdge: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return decodeThumbnail(source: source, maxPixelSize: maxLongEdge)
    }

    /// 统一解码入口。
    ///
    /// 策略：**保留 `kCGImageSourceCreateThumbnailWithTransform: true`**，让 ImageIO 处理
    /// 方向（对绝大多数图片正确）。然后仅对 orientation 5-8（会交换宽高的旋转）做
    /// **尺寸验证**：如果输出的横竖方向与预期不符，说明 ImageIO 未应用变换，此时手动补救。
    /// orientation 2-4（不交换宽高的翻转/180°）无法通过尺寸检测，信任 ImageIO。
    private static func decodeThumbnail(source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1

        guard orientation >= 5, orientation <= 8 else {
            return image
        }

        let srcW = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let srcH = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard srcW > 0, srcH > 0, srcW != srcH else {
            return image
        }

        let srcIsLandscape = srcW > srcH
        let resultIsLandscape = image.width > image.height

        if srcIsLandscape == resultIsLandscape {
            return applyOrientation(image, orientation: orientation) ?? image
        }

        return image
    }

    /// 手动应用 EXIF orientation 变换（仅用于 ImageIO 未正确处理的补救场景）。
    private static func applyOrientation(_ image: CGImage, orientation: UInt32) -> CGImage? {
        let w = image.width
        let h = image.height

        let swapsWidthHeight = orientation >= 5 && orientation <= 8
        let drawWidth = swapsWidthHeight ? h : w
        let drawHeight = swapsWidthHeight ? w : h

        guard let ctx = CGContext(
            data: nil,
            width: drawWidth,
            height: drawHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high

        switch orientation {
        case 2: // Mirror horizontal
            ctx.translateBy(x: CGFloat(drawWidth), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case 3: // Rotate 180°
            ctx.translateBy(x: CGFloat(drawWidth), y: CGFloat(drawHeight))
            ctx.rotate(by: CGFloat.pi)
        case 4: // Mirror vertical
            ctx.translateBy(x: 0, y: CGFloat(drawHeight))
            ctx.scaleBy(x: 1, y: -1)
        case 5: // Mirror horizontal + rotate 270° CW
            ctx.translateBy(x: CGFloat(drawWidth), y: 0)
            ctx.rotate(by: CGFloat.pi / 2)
            ctx.scaleBy(x: 1, y: -1)
        case 6: // Rotate 90° CW
            ctx.translateBy(x: CGFloat(drawWidth), y: 0)
            ctx.rotate(by: CGFloat.pi / 2)
        case 7: // Mirror horizontal + rotate 90° CW
            ctx.translateBy(x: 0, y: CGFloat(drawHeight))
            ctx.rotate(by: -CGFloat.pi / 2)
            ctx.scaleBy(x: 1, y: -1)
        case 8: // Rotate 270° CW
            ctx.translateBy(x: 0, y: CGFloat(drawHeight))
            ctx.rotate(by: -CGFloat.pi / 2)
        default:
            return nil
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func fallbackMetadata(for url: URL) -> EXIFData {
        EXIFData(
            captureDate: fileCreationDate(for: url),
            gpsCoordinate: nil,
            focalLength: nil,
            aperture: nil,
            shutterSpeed: nil,
            iso: nil,
            cameraModel: nil,
            lensModel: nil,
            imageWidth: 0,
            imageHeight: 0
        )
    }

    private static func fileCreationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
    }

    private static func parseDate(exif: [CFString: Any]?, tiff: [CFString: Any]?) -> Date? {
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    private static func parseCoordinate(_ gps: [CFString: Any]?) -> Coordinate? {
        guard let gps else { return nil }
        guard var latitude = numericValue(gps[kCGImagePropertyGPSLatitude]),
              var longitude = numericValue(gps[kCGImagePropertyGPSLongitude]) else {
            return nil
        }

        if let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String, latitudeRef.uppercased() == "S" {
            latitude *= -1
        }
        if let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String, longitudeRef.uppercased() == "W" {
            longitude *= -1
        }

        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func parseShutterSpeed(_ exif: [CFString: Any]?) -> String? {
        if let exposureTime = numericValue(exif?[kCGImagePropertyExifExposureTime]), exposureTime > 0 {
            if exposureTime < 1 {
                let denominator = Int((1 / exposureTime).rounded())
                return "1/\(max(1, denominator))"
            }
            return String(format: "%.1fs", exposureTime)
        }
        return nil
    }

    private static func parseISO(_ exif: [CFString: Any]?) -> Int? {
        if let array = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Double], let first = array.first {
            return Int(first)
        }
        return nil
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        default:
            return nil
        }
    }
}
