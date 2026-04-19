import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Luma

enum TestFixtures {
    static let shanghaiTimeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!

    static func makeDate(
        year: Int = 2026,
        month: Int = 4,
        day: Int = 4,
        hour: Int,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone = shanghaiTimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    static func makeAIScore(
        provider: String = "local",
        overall: Int = 80,
        recommended: Bool = false,
        comment: String = "Looks good",
        timestamp: Date = makeDate(hour: 9)
    ) -> AIScore {
        AIScore(
            provider: provider,
            scores: PhotoScores(
                composition: overall,
                exposure: overall,
                color: overall,
                sharpness: overall,
                story: overall
            ),
            overall: overall,
            comment: comment,
            recommended: recommended,
            timestamp: timestamp
        )
    }

    static func makeAsset(
        id: UUID = UUID(),
        baseName: String,
        captureDate: Date,
        coordinate: Coordinate? = nil,
        aiScore: AIScore? = nil,
        importResumeKey: String? = nil,
        userDecision: Decision = .pending,
        userRating: Int? = nil,
        issues: [AssetIssue] = []
    ) -> MediaAsset {
        MediaAsset(
            id: id,
            importResumeKey: importResumeKey ?? baseName.lowercased(),
            baseName: baseName,
            source: .folder(path: "/tmp/source"),
            previewURL: nil,
            rawURL: nil,
            livePhotoVideoURL: nil,
            depthData: false,
            thumbnailURL: nil,
            metadata: EXIFData(
                captureDate: captureDate,
                gpsCoordinate: coordinate,
                focalLength: 50,
                aperture: 1.8,
                shutterSpeed: "1/125",
                iso: 100,
                cameraModel: "Test Camera",
                lensModel: "Test Lens",
                imageWidth: 6000,
                imageHeight: 4000
            ),
            mediaType: .photo,
            importState: .complete,
            aiScore: aiScore,
            editSuggestions: nil,
            userDecision: userDecision,
            userRating: userRating,
            issues: issues
        )
    }

    static func withTemporaryDirectory<Result>(
        prefix: String = "LumaTests",
        _ body: (URL) throws -> Result
    ) throws -> Result {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    @MainActor
    static func withTemporaryDirectory<Result>(
        prefix: String = "LumaTests",
        _ body: (URL) async throws -> Result
    ) async throws -> Result {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    static func createFile(at url: URL, modifiedAt: Date) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data("fixture".utf8))
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    static func makeJPEG(at url: URL, size: CGSize = CGSize(width: 4, height: 4)) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = Int(size.width) * 4
        var pixels = [UInt8](repeating: 0, count: Int(size.height) * bytesPerRow)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 220
            pixels[index + 1] = 120
            pixels[index + 2] = 80
            pixels[index + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw NSError(domain: "TestFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create test JPEG"])
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "TestFixtures", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG destination"])
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "TestFixtures", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize test JPEG"])
        }
    }

    static func withAppSupportRootOverride<Result>(
        _ rootURL: URL,
        body: () throws -> Result
    ) throws -> Result {
        let key = "LUMA_APP_SUPPORT_ROOT"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, rootURL.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        return try body()
    }

    @MainActor
    static func withAppSupportRootOverride<Result>(
        _ rootURL: URL,
        body: () async throws -> Result
    ) async throws -> Result {
        let key = "LUMA_APP_SUPPORT_ROOT"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, rootURL.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        return try await body()
    }

    static func makeGroup(
        name: String,
        assets: [MediaAsset],
        recommendedAssets: [UUID] = [],
        groupComment: String? = nil
    ) -> PhotoGroup {
        let sortedAssets = assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        return PhotoGroup(
            id: UUID(),
            name: name,
            assets: sortedAssets.map(\.id),
            subGroups: sortedAssets.map { asset in
                SubGroup(id: UUID(), assets: [asset.id], bestAsset: recommendedAssets.contains(asset.id) ? asset.id : nil)
            },
            timeRange: sortedAssets.first!.metadata.captureDate ... sortedAssets.last!.metadata.captureDate,
            location: sortedAssets.first?.metadata.gpsCoordinate,
            groupComment: groupComment,
            recommendedAssets: recommendedAssets
        )
    }

    static func makeImportSession(
        id: UUID = UUID(),
        source: ImportSourceDescriptor = .folder(path: "/tmp/inbox", displayName: "Inbox"),
        projectDirectory: URL,
        projectName: String = "Test Project",
        createdAt: Date = makeDate(hour: 9),
        updatedAt: Date = makeDate(hour: 9, minute: 5),
        phase: ImportPhase,
        status: ImportSessionStatus,
        totalItems: Int = 10,
        completedThumbnails: Int = 0,
        completedPreviews: Int = 0,
        completedOriginals: Int = 0,
        lastError: String? = nil
    ) -> ImportSession {
        ImportSession(
            id: id,
            source: source,
            projectDirectory: projectDirectory,
            projectName: projectName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            phase: phase,
            status: status,
            totalItems: totalItems,
            completedThumbnails: completedThumbnails,
            completedPreviews: completedPreviews,
            completedOriginals: completedOriginals,
            lastError: lastError,
            completedAt: nil,
            importedAssetIDs: []
        )
    }

    static func makeManifest(
        name: String,
        createdAt: Date = makeDate(hour: 9),
        assets: [MediaAsset],
        groups: [PhotoGroup]
    ) -> ExpeditionManifest {
        ExpeditionManifest(
            id: UUID(),
            name: name,
            createdAt: createdAt,
            assets: assets,
            groups: groups
        )
    }

    static func writeManifest(_ manifest: ExpeditionManifest, in directory: URL) throws {
        let data = try JSONEncoder.lumaEncoder.encode(manifest)
        try data.write(to: AppDirectories.manifestURL(in: directory), options: [.atomic])
    }

    /// Seeds `ProjectStore` with an in-memory expedition so `assets` / `groups` setters work under @testable.
    @MainActor
    static func seedStore(
        _ store: ProjectStore,
        name: String = "Test",
        assets: [MediaAsset],
        groups: [PhotoGroup] = []
    ) {
        let id = UUID()
        let expedition = Expedition(
            id: id,
            name: name,
            createdAt: .now,
            updatedAt: .now,
            location: nil,
            tags: [],
            coverAssetID: assets.first?.id,
            assets: assets,
            groups: groups,
            importSessions: [],
            editingSessions: [],
            exportJobs: []
        )
        store.expeditions = [expedition]
        store.activeExpeditionID = id
        store.currentManifestID = id
    }

}
