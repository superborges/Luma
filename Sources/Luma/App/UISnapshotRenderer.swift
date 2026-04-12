import AppKit
import Foundation
import SwiftUI

enum UISnapshotRenderer {
    private enum SnapshotViewMode {
        case fullWindow
        case gridOnly
        case sidebarOnly
    }

    private struct SnapshotRequest {
        let outputURL: URL
        let projectURL: URL?
        let size: NSSize
        let viewMode: SnapshotViewMode
    }

    static func requestedOutputURL(from arguments: [String]) -> URL? {
        if let inline = arguments.first(where: { $0.hasPrefix("--snapshot-ui=") }) {
            let path = String(inline.dropFirst("--snapshot-ui=".count))
            guard !path.isEmpty else { return nil }
            return URL(filePath: path)
        }

        guard let index = arguments.firstIndex(of: "--snapshot-ui"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(filePath: arguments[index + 1])
    }

    @MainActor
    static func render(to outputURL: URL, arguments: [String]) throws {
        let request = snapshotRequest(outputURL: outputURL, arguments: arguments)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: request.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let store = try makeStore(baseDirectory: request.outputURL.deletingLastPathComponent(), projectURL: request.projectURL)
        let size = request.size
        let rootView: AnyView
        switch request.viewMode {
        case .fullWindow:
            rootView = AnyView(
                ContentView(store: store)
                    .frame(width: size.width, height: size.height)
            )
        case .gridOnly:
            rootView = AnyView(
                PhotoGrid(store: store)
                    .frame(width: size.width, height: size.height)
            )
        case .sidebarOnly:
            rootView = AnyView(
                GroupSidebar(store: store)
                    .frame(width: size.width, height: size.height)
            )
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.displayIfNeeded()

        // Let SwiftUI run its initial tasks so the thumbnail cells can populate.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw LumaError.persistenceFailed("Unable to allocate UI snapshot buffer.")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw LumaError.persistenceFailed("Unable to encode UI snapshot PNG.")
        }

        try pngData.write(to: request.outputURL, options: [.atomic])
    }

    @MainActor
    private static func snapshotRequest(outputURL: URL, arguments: [String]) -> SnapshotRequest {
        SnapshotRequest(
            outputURL: outputURL,
            projectURL: requestedProjectURL(from: arguments),
            size: requestedSnapshotSize(from: arguments) ?? NSSize(width: 1440, height: 900),
            viewMode: requestedSnapshotViewMode(from: arguments)
        )
    }

    private static func requestedProjectURL(from arguments: [String]) -> URL? {
        if let inline = arguments.first(where: { $0.hasPrefix("--snapshot-project=") }) {
            let path = String(inline.dropFirst("--snapshot-project=".count))
            guard !path.isEmpty else { return nil }
            return URL(filePath: path)
        }

        guard let index = arguments.firstIndex(of: "--snapshot-project"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(filePath: arguments[index + 1])
    }

    private static func requestedSnapshotSize(from arguments: [String]) -> NSSize? {
        let rawValue: String?
        if let inline = arguments.first(where: { $0.hasPrefix("--snapshot-size=") }) {
            rawValue = String(inline.dropFirst("--snapshot-size=".count))
        } else if let index = arguments.firstIndex(of: "--snapshot-size"),
                  arguments.indices.contains(index + 1) {
            rawValue = arguments[index + 1]
        } else {
            rawValue = nil
        }

        guard let rawValue,
              let separator = rawValue.firstIndex(of: "x") ?? rawValue.firstIndex(of: "X") else {
            return nil
        }

        let width = Double(rawValue[..<separator])
        let height = Double(rawValue[rawValue.index(after: separator)...])
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }

        return NSSize(width: width, height: height)
    }

    private static func requestedSnapshotViewMode(from arguments: [String]) -> SnapshotViewMode {
        let rawValue: String?
        if let inline = arguments.first(where: { $0.hasPrefix("--snapshot-view=") }) {
            rawValue = String(inline.dropFirst("--snapshot-view=".count))
        } else if let index = arguments.firstIndex(of: "--snapshot-view"),
                  arguments.indices.contains(index + 1) {
            rawValue = arguments[index + 1]
        } else {
            rawValue = nil
        }

        switch rawValue?.lowercased() {
        case "grid":
            return .gridOnly
        case "sidebar":
            return .sidebarOnly
        default:
            return .fullWindow
        }
    }

    @MainActor
    private static func makeStore(baseDirectory: URL, projectURL: URL?) throws -> ProjectStore {
        if let projectURL {
            return try makeStore(from: projectURL)
        }
        return try makePreviewStore(baseDirectory: baseDirectory)
    }

    @MainActor
    private static func makeStore(from projectURL: URL) throws -> ProjectStore {
        let resolvedProjectURL: URL
        if projectURL.lastPathComponent == "manifest.json" {
            resolvedProjectURL = projectURL.deletingLastPathComponent()
        } else {
            resolvedProjectURL = projectURL
        }

        let manifestURL = resolvedProjectURL.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder.lumaDecoder.decode(ExpeditionManifest.self, from: data)

        let store = ProjectStore(enableImportMonitoring: false)
        store.currentProjectDirectory = resolvedProjectURL
        store.currentManifestID = manifest.id
        var expedition = manifest.expedition
        if expedition.id != manifest.id {
            expedition = Expedition(
                id: manifest.id,
                name: expedition.name,
                createdAt: expedition.createdAt,
                updatedAt: expedition.updatedAt,
                location: expedition.location,
                tags: expedition.tags,
                coverAssetID: expedition.coverAssetID,
                assets: expedition.assets,
                groups: expedition.groups,
                importSessions: expedition.importSessions,
                editingSessions: expedition.editingSessions,
                exportJobs: expedition.exportJobs
            )
        }
        store.expeditions = [expedition]
        store.activeExpeditionID = expedition.id
        store.selectedGroupID = expedition.groups.first?.id
        store.selectedAssetID = expedition.groups.first.flatMap { firstGroup in
            expedition.assets.first(where: { firstGroup.assets.contains($0.id) })?.id
        } ?? expedition.assets.first?.id
        store.displayMode = .grid
        store.localRejectedCount = expedition.assets.filter(\.isTechnicallyRejected).count
        return store
    }

    @MainActor
    private static func makePreviewStore(baseDirectory: URL) throws -> ProjectStore {
        let previewDirectory = baseDirectory.appendingPathComponent("ui-preview-assets", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)

        let projectName = "Luma · Kyoto Weekend"
        let startDate = ISO8601DateFormatter().date(from: "2026-03-18T08:00:00Z") ?? .now

        let assetBlueprints: [(String, String, Decision, Bool, [AssetIssue], Bool)] = [
            ("IMG_1024", "#D96C4C", .picked, true, [], false),
            ("IMG_1025", "#C59B57", .pending, true, [], true),
            ("IMG_1026", "#6B8BA4", .rejected, false, [.blurry], false),
            ("IMG_1027", "#7C9D6E", .picked, true, [], false),
            ("IMG_1101", "#B45A7A", .pending, false, [.underexposed], false),
            ("IMG_1102", "#5677A6", .picked, true, [], false),
            ("IMG_1103", "#A47B52", .pending, false, [], false),
            ("IMG_1104", "#4F8F86", .rejected, false, [.eyesClosed], false),
        ]

        var assets: [MediaAsset] = []
        for (index, blueprint) in assetBlueprints.enumerated() {
            let imageURL = previewDirectory.appendingPathComponent("\(blueprint.0).png")
            try createPreviewImage(at: imageURL, title: blueprint.0, hexColor: blueprint.1)

            let captureDate = startDate.addingTimeInterval(Double(index) * 90 * 60)
            let overall = 92 - (index * 6)
            let score = AIScore(
                provider: index < 4 ? "local-coreml" : "ollama-vision",
                scores: PhotoScores(
                    composition: max(52, overall - 3),
                    exposure: max(48, overall - 5),
                    color: max(55, overall - 1),
                    sharpness: max(38, overall - 8),
                    story: max(44, overall - 4)
                ),
                overall: max(38, overall),
                comment: index == 1 ? "构图稳定，人物与环境关系自然，值得精修。" : "色彩和氛围在线，适合保留到交付集。",
                recommended: blueprint.3,
                timestamp: .now
            )

            let editSuggestions: EditSuggestions? = index == 1 ? EditSuggestions(
                crop: CropSuggestion(
                    needed: true,
                    ratio: "4:5",
                    direction: "slightly tighter",
                    rule: "rule of thirds",
                    top: 0.03,
                    bottom: 0.04,
                    left: 0.02,
                    right: 0.05,
                    angle: -0.6
                ),
                filterStyle: FilterSuggestion(
                    primary: "Soft Film",
                    reference: "Portra 400",
                    mood: "温暖、轻微复古、空气感"
                ),
                adjustments: AdjustmentValues(
                    exposure: 0.25,
                    contrast: 8,
                    highlights: -18,
                    shadows: 14,
                    temperature: 5,
                    tint: 1,
                    saturation: 4,
                    vibrance: 11,
                    clarity: 6,
                    dehaze: 3
                ),
                hslAdjustments: nil,
                localEdits: nil,
                narrative: "保留人物与寺庙的关系，轻提阴影，压住天空高光。"
            ) : nil

            assets.append(
                MediaAsset(
                    id: UUID(),
                    importResumeKey: blueprint.0.lowercased(),
                    baseName: blueprint.0,
                    source: .folder(path: previewDirectory.path),
                    previewURL: imageURL,
                    rawURL: nil,
                    livePhotoVideoURL: blueprint.5 ? URL(filePath: "/tmp/\(blueprint.0).mov") : nil,
                    depthData: false,
                    thumbnailURL: imageURL,
                    metadata: EXIFData(
                        captureDate: captureDate,
                        gpsCoordinate: Coordinate(latitude: 35.0116 + Double(index) * 0.0014, longitude: 135.7681 + Double(index) * 0.0011),
                        focalLength: Double([24, 35, 50, 85][index % 4]),
                        aperture: [1.8, 2.8, 4.0, 5.6][index % 4],
                        shutterSpeed: ["1/250", "1/320", "1/125", "1/500"][index % 4],
                        iso: [100, 125, 200, 400][index % 4],
                        cameraModel: index < 4 ? "FUJIFILM X-T5" : "iPhone 16 Pro",
                        lensModel: index < 4 ? "XF 23mm F1.4" : "iPhone Main Camera 24mm",
                        imageWidth: 4032,
                        imageHeight: 3024
                    ),
                    mediaType: blueprint.5 ? .livePhoto : .photo,
                    importState: .complete,
                    aiScore: score,
                    editSuggestions: editSuggestions,
                    userDecision: blueprint.2,
                    userRating: nil,
                    issues: blueprint.4
                )
            )
        }

        let groupOneAssets = Array(assets.prefix(4))
        let groupTwoAssets = Array(assets.suffix(4))

        let groups = [
            PhotoGroup(
                id: UUID(),
                name: "京都 · 清水寺",
                assets: groupOneAssets.map(\.id),
                subGroups: [
                    SubGroup(id: UUID(), assets: groupOneAssets.map(\.id), bestAsset: groupOneAssets[1].id)
                ],
                timeRange: groupOneAssets[0].metadata.captureDate...groupOneAssets[3].metadata.captureDate,
                location: groupOneAssets[0].metadata.gpsCoordinate,
                groupComment: "游客密度高，但画面情绪完整。",
                recommendedAssets: groupOneAssets.filter { $0.aiScore?.recommended == true }.map(\.id)
            ),
            PhotoGroup(
                id: UUID(),
                name: "奈良 · 若草山",
                assets: groupTwoAssets.map(\.id),
                subGroups: [
                    SubGroup(id: UUID(), assets: groupTwoAssets.map(\.id), bestAsset: groupTwoAssets[1].id)
                ],
                timeRange: groupTwoAssets[0].metadata.captureDate...groupTwoAssets[3].metadata.captureDate,
                location: groupTwoAssets[0].metadata.gpsCoordinate,
                groupComment: "逆光和移动主体较多，建议人工复核。",
                recommendedAssets: groupTwoAssets.filter { $0.aiScore?.recommended == true }.map(\.id)
            ),
        ]

        let previewID = UUID()
        let expedition = Expedition(
            id: previewID,
            name: projectName,
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
        let store = ProjectStore(enableImportMonitoring: false)
        store.currentManifestID = previewID
        store.expeditions = [expedition]
        store.activeExpeditionID = previewID
        store.selectedGroupID = groups[0].id
        store.selectedAssetID = groupOneAssets[1].id
        store.displayMode = .grid
        store.localRejectedCount = assets.filter(\.isTechnicallyRejected).count
        return store
    }

    private static func createPreviewImage(at url: URL, title: String, hexColor: String) throws {
        let size = NSSize(width: 1280, height: 960)
        let image = NSImage(size: size)

        image.lockFocus()
        let baseColor = NSColor(hex: hexColor)
        let topColor = baseColor.highlight(withLevel: 0.25) ?? baseColor
        let bottomColor = baseColor.shadow(withLevel: 0.18) ?? baseColor
        let gradient = NSGradient(starting: topColor, ending: bottomColor)
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

        NSColor.white.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 80, width: 1140, height: 800), xRadius: 32, yRadius: 32).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 76, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
            .paragraphStyle: paragraph,
        ]

        title.draw(in: NSRect(x: 110, y: 600, width: 900, height: 100), withAttributes: titleAttributes)
        "Luma Preview Frame".draw(in: NSRect(x: 112, y: 538, width: 520, height: 50), withAttributes: subtitleAttributes)

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw LumaError.persistenceFailed("Unable to encode preview image.")
        }

        try pngData.write(to: url, options: [.atomic])
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: value)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
