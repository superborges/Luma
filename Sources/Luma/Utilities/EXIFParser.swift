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

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 中央大图用：若整图长边不超过 `maxLongEdge`，直接 `CreateImageAtIndex` 解码主图，
    /// 避免 `CreateThumbnailAtIndex` 在 HEIC/JPEG 上命中**内嵌小缩略图**导致永远发糊。
    /// 若超过预算则退回 `makeThumbnail` 做降采样。
    static func cgImageForDisplay(at url: URL, maxLongEdge: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let longEdge = max(w, h)
            if longEdge > 0, longEdge <= maxLongEdge {
                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                if let full = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
                    return full
                }
            }
        }

        return makeThumbnail(from: url, maxPixelSize: maxLongEdge)
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
