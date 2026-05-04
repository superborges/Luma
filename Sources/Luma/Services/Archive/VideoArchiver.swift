import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ArchiveResult: Codable, Hashable {
    let outputDirectory: URL
    let generatedFiles: [URL]
    let skippedCount: Int
    let freedBytes: Int64
}

struct ArchiveProgress: Sendable {
    let completed: Int
    let total: Int
    let currentName: String
}

struct VideoArchiver {

    // MARK: - Archive Video

    func archive(
        groups: [PhotoGroup],
        assets: [MediaAsset],
        batchName: String,
        onProgress: (@Sendable (ArchiveProgress) -> Void)? = nil
    ) async throws -> ArchiveResult {
        try await Task.detached(priority: .utility) {
            try archiveSync(groups: groups, assets: assets, batchName: batchName, onProgress: onProgress)
        }.value
    }

    // MARK: - Shrink & Keep

    func shrinkKeep(
        assets: [MediaAsset],
        batchName: String,
        onProgress: (@Sendable (ArchiveProgress) -> Void)? = nil
    ) async throws -> ArchiveResult {
        try await Task.detached(priority: .utility) {
            try shrinkKeepSync(assets: assets, batchName: batchName, onProgress: onProgress)
        }.value
    }

    private func shrinkKeepSync(
        assets: [MediaAsset],
        batchName: String,
        onProgress: (@Sendable (ArchiveProgress) -> Void)?
    ) throws -> ArchiveResult {
        let destinationRoot = try AppDirectories.archiveBatchDirectory(named: batchName)
        let shrunkRoot = destinationRoot.appendingPathComponent("shrunk", isDirectory: true)
        try FileManager.default.createDirectory(at: shrunkRoot, withIntermediateDirectories: true)

        var generatedFiles: [URL] = []
        var manifestEntries: [ArchiveManifestEntry] = []
        var skippedCount = 0
        var freedBytes: Int64 = 0

        for (index, asset) in assets.enumerated() {
            onProgress?(ArchiveProgress(completed: index, total: assets.count, currentName: asset.baseName))

            guard let sourceURL = asset.previewURL ?? asset.rawURL else {
                skippedCount += 1
                continue
            }
            guard let image = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 2048) else {
                skippedCount += 1
                continue
            }

            let fileName = "\(AppDirectories.sanitizePathComponent(asset.baseName)).jpg"
            let destinationURL = shrunkRoot.appendingPathComponent(fileName)

            do {
                try writeJPEG(image: image, to: destinationURL, metadataFrom: sourceURL)
                generatedFiles.append(destinationURL)

                if let rawURL = asset.rawURL,
                   rawURL != sourceURL,
                   FileManager.default.fileExists(atPath: rawURL.path) {
                    let rawSize = (try? rawURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    do {
                        try FileManager.default.removeItem(at: rawURL)
                        freedBytes += rawSize
                    } catch {
                        // RAW deletion is best-effort; keep shrunk output
                    }
                }

                manifestEntries.append(
                    ArchiveManifestEntry(
                        originalFileName: sourceURL.lastPathComponent,
                        outputFileName: destinationURL.lastPathComponent,
                        captureDate: asset.metadata.captureDate,
                        aiScore: asset.aiScore?.overall,
                        archiveMethod: "shrinkKeep"
                    )
                )
            } catch {
                skippedCount += 1
            }
        }

        let manifest = ArchiveManifest(batchName: batchName, videos: [], entries: manifestEntries)
        let data = try JSONEncoder.lumaEncoder.encode(manifest)
        try data.write(to: destinationRoot.appendingPathComponent("archive_manifest.json"), options: [.atomic])

        return ArchiveResult(outputDirectory: destinationRoot, generatedFiles: generatedFiles, skippedCount: skippedCount, freedBytes: freedBytes)
    }

    // MARK: - Discard

    func discard(assets: [MediaAsset], onProgress: (@Sendable (ArchiveProgress) -> Void)? = nil) async -> (deletedCount: Int, freedBytes: Int64) {
        await Task.detached(priority: .utility) {
            Self.discardSync(assets: assets, onProgress: onProgress)
        }.value
    }

    private static func discardSync(assets: [MediaAsset], onProgress: (@Sendable (ArchiveProgress) -> Void)?) -> (deletedCount: Int, freedBytes: Int64) {
        var deletedCount = 0
        var freedBytes: Int64 = 0
        let fm = FileManager.default

        for (index, asset) in assets.enumerated() {
            onProgress?(ArchiveProgress(completed: index, total: assets.count, currentName: asset.baseName))

            for url in [asset.previewURL, asset.rawURL, asset.thumbnailURL].compactMap({ $0 }) {
                guard fm.fileExists(atPath: url.path) else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                do {
                    try fm.removeItem(at: url)
                    freedBytes += size
                    deletedCount += 1
                } catch {
                    // best-effort deletion
                }
            }
        }

        return (deletedCount, freedBytes)
    }

    // MARK: - Disk Space Estimation

    static func estimateArchiveSize(assets: [MediaAsset], handling: RejectedHandling) -> Int64 {
        switch handling {
        case .discard:
            return 0
        case .shrinkKeep:
            return Int64(assets.count) * 800_000
        case .archiveVideo:
            let totalSeconds = Double(assets.count) * 1.5 + 1.0
            return Int64(totalSeconds * 1_000_000)
        }
    }

    static func estimateFreedSpace(assets: [MediaAsset], handling: RejectedHandling) -> Int64 {
        switch handling {
        case .discard:
            return totalFileSize(of: assets)
        case .shrinkKeep:
            var freed: Int64 = 0
            for asset in assets {
                if let rawURL = asset.rawURL, asset.previewURL != nil {
                    freed += fileSize(rawURL)
                }
            }
            return freed
        case .archiveVideo:
            return 0
        }
    }

    private static func totalFileSize(of assets: [MediaAsset]) -> Int64 {
        var total: Int64 = 0
        for asset in assets {
            for url in [asset.previewURL, asset.rawURL, asset.thumbnailURL].compactMap({ $0 }) {
                total += fileSize(url)
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    // MARK: - Private: JPEG Writing

    private func writeJPEG(image: CGImage, to url: URL, metadataFrom sourceURL: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LumaError.persistenceFailed("Unable to create shrink archive image.")
        }

        var metadata: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
           let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            metadata = sourceProperties
        }
        metadata[kCGImageDestinationLossyCompressionQuality] = 0.8

        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LumaError.persistenceFailed("Unable to finalize shrink archive image.")
        }
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Private: Archive Video Sync

    private func archiveSync(
        groups: [PhotoGroup],
        assets: [MediaAsset],
        batchName: String,
        onProgress: (@Sendable (ArchiveProgress) -> Void)?
    ) throws -> ArchiveResult {
        let destinationRoot = try AppDirectories.archiveBatchDirectory(named: batchName)
        let assetsByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var generatedFiles: [URL] = []
        var videoEntries: [ArchiveVideoEntry] = []
        var skippedCount = 0
        let groupsToProcess = groups.filter { group in
            group.assets.contains { assetsByID[$0] != nil }
        }

        for (groupIndex, group) in groupsToProcess.enumerated() {
            onProgress?(ArchiveProgress(completed: groupIndex, total: groupsToProcess.count, currentName: group.name))

            let groupAssets = group.assets
                .compactMap { assetsByID[$0] }
                .filter { $0.userDecision != .picked && $0.primaryDisplayURL != nil }
                .sorted { $0.metadata.captureDate < $1.metadata.captureDate }

            guard !groupAssets.isEmpty else { continue }

            let fileName = String(
                format: "%02d_%@_archive.mp4",
                groupIndex + 1,
                AppDirectories.sanitizePathComponent(group.name)
            )
            let outputURL = destinationRoot.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            do {
                let entry = try createVideo(for: group, assets: groupAssets, outputURL: outputURL)
                generatedFiles.append(outputURL)
                videoEntries.append(entry)
            } catch {
                skippedCount += 1
            }
        }

        let manifest = ArchiveManifest(batchName: batchName, videos: videoEntries, entries: [])
        let manifestData = try JSONEncoder.lumaEncoder.encode(manifest)
        try manifestData.write(to: destinationRoot.appendingPathComponent("archive_manifest.json"), options: [.atomic])

        return ArchiveResult(outputDirectory: destinationRoot, generatedFiles: generatedFiles, skippedCount: skippedCount, freedBytes: 0)
    }

    // MARK: - Private: Video Creation

    private func createVideo(for group: PhotoGroup, assets: [MediaAsset], outputURL: URL) throws -> ArchiveVideoEntry {
        var renderer = ArchiveVideoRenderer()
        let renderAssets = assets.compactMap { asset -> RenderAsset? in
            guard let sourceURL = asset.primaryDisplayURL else { return nil }
            guard let cgImage = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 2200) else { return nil }
            return RenderAsset(asset: asset, image: CIImage(cgImage: cgImage), motion: MotionStyle(seed: asset.id.uuidString))
        }

        guard !renderAssets.isEmpty else {
            throw LumaError.unsupported("No renderable assets available for archive video.")
        }

        let videoSize = CGSize(width: 1920, height: 1080)
        let fps: Int32 = 30
        let secondsPerPhoto = 1.5
        let titleDuration = 1.0
        let transitionDuration = 0.3
        let titleFrames = Int(titleDuration * Double(fps))
        let framesPerPhoto = Int(secondsPerPhoto * Double(fps))
        let transitionFrames = Int(transitionDuration * Double(fps))
        let totalFrames = titleFrames + renderAssets.count * framesPerPhoto

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height),
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw LumaError.persistenceFailed("Unable to configure archive video writer.")
        }
        writer.add(writerInput)

        let titleCard = renderer.makeTitleCard(for: group, size: videoSize)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_Hans")
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }

            let image: CIImage
            if frameIndex < titleFrames {
                image = titleCard
            } else {
                let localFrame = frameIndex - titleFrames
                let assetIndex = localFrame / framesPerPhoto
                let frameInAsset = localFrame % framesPerPhoto
                let current = renderAssets[assetIndex]
                let currentProgress = Double(frameInAsset) / Double(max(framesPerPhoto - 1, 1))
                var currentFrame = renderer.renderFrame(for: current, progress: currentProgress, canvasSize: videoSize)

                currentFrame = renderer.overlayBottomBar(
                    on: currentFrame,
                    groupName: group.name,
                    date: dateFormatter.string(from: current.asset.metadata.captureDate),
                    location: group.location.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) },
                    canvasSize: videoSize
                )

                if assetIndex < renderAssets.count - 1, frameInAsset >= framesPerPhoto - transitionFrames {
                    let next = renderAssets[assetIndex + 1]
                    let transitionProgress = Double(frameInAsset - (framesPerPhoto - transitionFrames)) / Double(max(transitionFrames - 1, 1))
                    var nextFrame = renderer.renderFrame(for: next, progress: transitionProgress, canvasSize: videoSize)
                    nextFrame = renderer.overlayBottomBar(
                        on: nextFrame,
                        groupName: group.name,
                        date: dateFormatter.string(from: next.asset.metadata.captureDate),
                        location: group.location.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) },
                        canvasSize: videoSize
                    )
                    image = renderer.dissolve(from: currentFrame, to: nextFrame, progress: transitionProgress, canvasSize: videoSize)
                } else {
                    image = currentFrame
                }
            }

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            let pixelBuffer = try renderer.makePixelBuffer(from: adaptor, size: videoSize)
            renderer.render(image: image, to: pixelBuffer, size: videoSize)

            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                throw writer.error ?? LumaError.persistenceFailed("Failed to append archive video frame.")
            }
        }

        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        if writer.status != .completed {
            throw writer.error ?? LumaError.persistenceFailed("Failed to finalize archive video.")
        }

        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let items = renderAssets.enumerated().map { index, renderAsset in
            ArchiveVideoItem(
                originalFileName: renderAsset.sourceFileName,
                captureDate: renderAsset.asset.metadata.captureDate,
                aiScore: renderAsset.asset.aiScore?.overall,
                startTime: titleDuration + (Double(index) * secondsPerPhoto),
                endTime: titleDuration + (Double(index + 1) * secondsPerPhoto)
            )
        }

        return ArchiveVideoEntry(
            fileName: outputURL.lastPathComponent,
            groupName: group.name,
            photoCount: renderAssets.count,
            duration: Double(totalFrames) / Double(fps),
            fileSize: fileSize,
            items: items
        )
    }
}

// MARK: - Manifest Models (internal for testability)

struct ArchiveManifest: Codable, Hashable {
    let batchName: String
    let videos: [ArchiveVideoEntry]
    let entries: [ArchiveManifestEntry]
}

struct ArchiveManifestEntry: Codable, Hashable {
    let originalFileName: String
    let outputFileName: String
    let captureDate: Date
    let aiScore: Int?
    let archiveMethod: String
}

struct ArchiveVideoEntry: Codable, Hashable {
    let fileName: String
    let groupName: String
    let photoCount: Int
    let duration: Double
    let fileSize: Int64
    let items: [ArchiveVideoItem]
}

struct ArchiveVideoItem: Codable, Hashable {
    let originalFileName: String
    let captureDate: Date
    let aiScore: Int?
    let startTime: Double
    let endTime: Double
}

// MARK: - Render Types

private struct RenderAsset {
    let asset: MediaAsset
    let image: CIImage
    let motion: MotionStyle

    var sourceFileName: String {
        asset.primaryDisplayURL?.lastPathComponent ?? asset.baseName
    }
}

private enum MotionStyle {
    case zoomIn
    case zoomOut
    case panLeft
    case panRight

    init(seed: String) {
        let value = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        switch value % 4 {
        case 0:
            self = .zoomIn
        case 1:
            self = .zoomOut
        case 2:
            self = .panLeft
        default:
            self = .panRight
        }
    }
}

// MARK: - Video Renderer

private struct ArchiveVideoRenderer {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var barCache: [String: CIImage] = [:]

    func renderFrame(for renderAsset: RenderAsset, progress: Double, canvasSize: CGSize) -> CIImage {
        let foregroundRect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 50, dy: 50)
        let background = fittedImage(renderAsset.image, in: CGRect(origin: .zero, size: canvasSize), mode: .fill)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28])
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.9,
                kCIInputBrightnessKey: -0.08,
                kCIInputContrastKey: 1.05,
            ])

        let fitImage = fittedImage(renderAsset.image, in: foregroundRect, mode: .fit)
        let animatedForeground = applyMotion(renderAsset.motion, to: fitImage, in: foregroundRect, progress: progress)

        return animatedForeground
            .composited(over: background)
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    mutating func overlayBottomBar(on image: CIImage, groupName: String, date: String, location: String?, canvasSize: CGSize) -> CIImage {
        var parts = [groupName, date]
        if let loc = location { parts.append(loc) }
        let cacheKey = parts.joined(separator: "\u{0}")

        let barCI: CIImage
        if let cached = barCache[cacheKey] {
            barCI = cached
        } else if let rendered = renderBarImage(text: parts.joined(separator: "  ·  "), canvasWidth: canvasSize.width) {
            barCache[cacheKey] = rendered
            barCI = rendered
        } else {
            return image
        }
        return barCI.composited(over: image).cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    private func renderBarImage(text: String, canvasWidth: CGFloat) -> CIImage? {
        let barHeight: CGFloat = 56
        let barRect = CGRect(x: 0, y: 0, width: canvasWidth, height: barHeight)
        let width = Int(canvasWidth)
        let height = Int(barHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.fill(barRect)

        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 18, nil)
        let textColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
        drawText(text, font: font, color: textColor, at: CGPoint(x: 24, y: 18), in: ctx)
        ctx.restoreGState()

        guard let barImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: barImage)
    }

    func dissolve(from current: CIImage, to next: CIImage, progress: Double, canvasSize: CGSize) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = current
        filter.targetImage = next
        filter.time = Float(progress)
        return (filter.outputImage ?? current).cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    func makePixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor, size: CGSize) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else {
            throw LumaError.persistenceFailed("Missing pixel buffer pool for archive writer.")
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw LumaError.persistenceFailed("Unable to allocate archive pixel buffer.")
        }
        return pixelBuffer
    }

    func render(image: CIImage, to pixelBuffer: CVPixelBuffer, size: CGSize) {
        ArchiveVideoRenderer.ciContext.render(
            image,
            to: pixelBuffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }

    func makeTitleCard(for group: PhotoGroup, size: CGSize) -> CIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: size))
        }

        let gradientColors = [CGColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1), CGColor(red: 0.16, green: 0.15, blue: 0.20, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
        context.fill(CGRect(x: 120, y: 120, width: size.width - 240, height: 240))

        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 84, nil)
        let subtitleFont = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 34, nil)
        drawText(group.name, font: titleFont, color: CGColor.white, at: CGPoint(x: 160, y: 330), in: context)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let subtitleParts = [
            formatter.string(from: group.timeRange.lowerBound),
            group.location.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) }
        ].compactMap { $0 }
        drawText(subtitleParts.joined(separator: " · "), font: subtitleFont, color: CGColor(gray: 1, alpha: 0.82), at: CGPoint(x: 160, y: 240), in: context)

        context.restoreGState()

        guard let cgImage = context.makeImage() else {
            return CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: size))
        }
        return CIImage(cgImage: cgImage)
    }

    private func drawText(_ text: String, font: CTFont, color: CGColor, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func fittedImage(_ image: CIImage, in rect: CGRect, mode: ScaleMode) -> CIImage {
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        let scaleX = rect.width / normalized.extent.width
        let scaleY = rect.height / normalized.extent.height
        let scale = mode == .fit ? min(scaleX, scaleY) : max(scaleX, scaleY)
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translated = scaled.transformed(
            by: CGAffineTransform(
                translationX: rect.midX - scaled.extent.width / 2,
                y: rect.midY - scaled.extent.height / 2
            )
        )
        return translated
    }

    private func applyMotion(_ motion: MotionStyle, to image: CIImage, in rect: CGRect, progress: Double) -> CIImage {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let panDistance = rect.width * 0.06
        let scale: Double
        let translationX: Double

        switch motion {
        case .zoomIn:
            scale = 1 + (0.08 * progress)
            translationX = 0
        case .zoomOut:
            scale = 1.08 - (0.08 * progress)
            translationX = 0
        case .panLeft:
            scale = 1.03
            translationX = -panDistance * progress
        case .panRight:
            scale = 1.03
            translationX = panDistance * progress
        }

        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x + translationX / scale, y: -center.y)

        return image.transformed(by: transform)
    }

    private enum ScaleMode {
        case fit
        case fill
    }
}
