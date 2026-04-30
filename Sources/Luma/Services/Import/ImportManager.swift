import AppKit
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

private actor ImportConnectionTracker {
    private let sourceName: String
    private var latestState: ConnectionState = .connected

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func update(_ state: ConnectionState) {
        latestState = state
    }

    func ensureConnected() throws {
        switch latestState {
        case .connected, .scanning:
            return
        case .disconnected:
            throw LumaError.importFailed("\(sourceName) 已断开连接，请重新连接后继续导入。")
        case .unavailable:
            throw LumaError.importFailed("\(sourceName) 当前不可访问，请解锁设备或重新连接后继续导入。")
        }
    }
}

struct ImportedProject {
    let manifest: SessionManifest
    let directory: URL
}

struct ImportedProjectSnapshot {
    let manifest: SessionManifest
    let directory: URL
    let isFinal: Bool
}

struct ImportManager: Sendable {
    private let groupingEngine: GroupingEngine
    private static let logger = Logger(subsystem: "Luma", category: "ImportManager")

    init(groupingEngine: GroupingEngine = GroupingEngine()) {
        self.groupingEngine = groupingEngine
    }

    func mostRecentRecoverableSession() -> ImportSession? {
        try? ImportSessionStore.loadRecoverableSessions().first
    }

    func loadManifest(for session: ImportSession) throws -> SessionManifest {
        guard let projectDirectory = session.projectDirectory else {
            throw LumaError.importFailed("导入会话缺少项目目录。")
        }
        return try Self.loadManifest(from: projectDirectory)
    }

    func refreshGroupNames(for groups: [PhotoGroup]) async -> [PhotoGroup] {
        await groupingEngine.refreshGroupNames(for: groups)
    }

    @MainActor
    func importFolderSelection(
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        let panel = NSOpenPanel()
        panel.title = "Import Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedFolder = panel.url else {
            throw LumaError.userCancelled
        }

        let source = ImportSourceDescriptor.folder(
            path: selectedFolder.path,
            displayName: selectedFolder.lastPathComponent
        )
        return try await importFromSource(source, progress: progress, snapshot: snapshot)
    }

    @MainActor
    func importSDCardSelection(
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        let availableVolumes = SDCardAdapter.availableVolumes()
        guard !availableVolumes.isEmpty else {
            throw LumaError.unsupported("未检测到包含 DCIM 的 SD 卡。")
        }

        let selectedVolume: URL
        if availableVolumes.count == 1 {
            selectedVolume = availableVolumes[0]
        } else {
            let panel = NSOpenPanel()
            panel.title = "Import SD Card"
            panel.directoryURL = URL(filePath: "/Volumes", directoryHint: .isDirectory)
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false

            guard panel.runModal() == .OK, let volume = panel.url else {
                throw LumaError.userCancelled
            }

            guard SDCardAdapter.isSupportedVolume(volume) else {
                throw LumaError.unsupported("请选择包含 DCIM 的 SD 卡卷宗。")
            }

            selectedVolume = volume
        }

        let source = ImportSourceDescriptor.sdCard(
            volumePath: selectedVolume.path,
            displayName: selectedVolume.lastPathComponent
        )
        return try await importFromSource(source, progress: progress, snapshot: snapshot)
    }

    @MainActor
    func importPhotosLibrarySelection(
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        let limit = try chooseRecentPhotosLimit()
        let displayName = "照片 App · 最近 \(limit) 张"
        let source = ImportSourceDescriptor.photosLibrary(
            albumLocalIdentifier: nil,
            limit: limit,
            displayName: displayName
        )
        return try await importFromSource(source, progress: progress, snapshot: snapshot)
    }

    /// 月份选择导入：UI 已选好月份，直接走 PhotosLibraryAdapter（多日期范围）。
    func importPhotosLibrary(
        plan: PhotosImportPlan,
        excludedLocalIdentifiers: Set<String> = [],
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        let displayName = plan.displayName
        let source = ImportSourceDescriptor.photosLibrary(
            albumLocalIdentifier: nil,
            limit: plan.limit,
            displayName: displayName
        )
        let adapter = PhotosLibraryAdapter(
            limit: plan.limit,
            dateRanges: plan.dateRanges,
            mediaTypeFilter: plan.mediaTypeFilter,
            excludedLocalIdentifiers: plan.dedupeAgainstCurrentProject ? excludedLocalIdentifiers : []
        )
        return try await importFromSource(source, adapter: adapter, progress: progress, snapshot: snapshot)
    }

    @MainActor
    func importIPhoneSelection(
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        let devices = await iPhoneAdapter.availableDevices()
        let unlockedDevices = devices.filter { !$0.isAccessRestricted }

        if unlockedDevices.isEmpty {
            if devices.isEmpty {
                throw LumaError.unsupported("未检测到已连接的 iPhone/iPad。请通过 USB 连接设备后重试。")
            }
            throw LumaError.unsupported("已检测到 Apple 设备，但它仍未解锁或未在手机上点击“信任此电脑”。")
        }

        let selectedDevice = try chooseIPhoneDevice(from: unlockedDevices)
        let source = ImportSourceDescriptor.iPhone(
            deviceID: selectedDevice.id,
            deviceName: selectedDevice.name
        )
        return try await importFromSource(source, progress: progress, snapshot: snapshot)
    }

    func importFromSource(
        _ source: ImportSourceDescriptor,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        try await importFromSource(
            source,
            adapter: makeAdapter(for: source),
            progress: progress,
            snapshot: snapshot
        )
    }

    func importFromSource(
        _ source: ImportSourceDescriptor,
        adapter: any ImportSourceAdapter,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        let createdAt = Date()
        let projectDirectory = try AppDirectories.createProjectDirectory(
            named: source.suggestedProjectName,
            createdAt: createdAt
        )

        var session = ImportSession(
            id: UUID(),
            source: source,
            projectDirectory: projectDirectory,
            projectName: source.suggestedProjectName,
            createdAt: createdAt,
            updatedAt: createdAt,
            phase: .scanning,
            status: .running,
            totalItems: 0,
            completedThumbnails: 0,
            completedPreviews: 0,
            completedOriginals: 0,
            lastError: nil,
            completedAt: nil,
            importedAssetIDs: []
        )

        try ImportSessionStore.save(session)

        do {
            return try await runImport(
                adapter: adapter,
                session: &session,
                existingManifest: nil,
                progress: progress,
                snapshot: snapshot
            )
        } catch {
            if session.totalItems == 0 {
                try? ImportSessionStore.delete(session)
                try? FileManager.default.removeItem(at: projectDirectory)
            }
            throw error
        }
    }

    func resumeImport(
        session: ImportSession,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        try await resumeImport(
            session: session,
            adapter: makeAdapter(for: session.source),
            progress: progress,
            snapshot: snapshot
        )
    }

    func resumeImport(
        session: ImportSession,
        adapter: any ImportSourceAdapter,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        var session = session
        session.status = .running
        session.phase = .scanning
        session.lastError = nil
        session.updatedAt = .now
        try ImportSessionStore.save(session)

        guard let projectDirectory = session.projectDirectory else {
            throw LumaError.importFailed("导入会话缺少项目目录。")
        }
        let manifest = try Self.loadManifest(from: projectDirectory)

        return try await runImport(
            adapter: adapter,
            session: &session,
            existingManifest: manifest,
            progress: progress,
            snapshot: snapshot
        )
    }

    private func runImport(
        adapter: any ImportSourceAdapter,
        session: inout ImportSession,
        existingManifest: SessionManifest?,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        snapshot: @escaping @Sendable (ImportedProjectSnapshot) -> Void
    ) async throws -> ImportedProject {
        guard let projectDirectory = session.projectDirectory else {
            throw LumaError.importFailed("导入会话缺少项目目录。")
        }
        let importStartedAt = ProcessInfo.processInfo.systemUptime
        Self.traceEvent(
            "import_run_started",
            metadata: traceMetadata(
                session: session,
                extra: ["resume": existingManifest == nil ? "false" : "true"]
            )
        )
        progress(.init(phase: .scanning, completed: 0, total: max(session.totalItems, 1), currentItemName: session.source.displayName))

        let connectionTracker = ImportConnectionTracker(sourceName: session.source.displayName)
        let connectionStates = adapter.connectionState
        let connectionMonitorTask = Task {
            for await state in connectionStates {
                await connectionTracker.update(state)
            }
        }
        defer {
            connectionMonitorTask.cancel()
        }

        let discoveredItems: [DiscoveredItem]
        do {
            let enumerateStartedAt = ProcessInfo.processInfo.systemUptime
            try await connectionTracker.ensureConnected()
            if case .photosLibrary = session.source {
                ImportPathBreadcrumb.mark(
                    "import_manager_photos_enumerate_await",
                    [
                        "session": session.id.uuidString,
                        "source": session.source.stableID
                    ]
                )
            }
            discoveredItems = try await adapter.enumerate()
            Self.traceMetric(
                "import_source_enumerated",
                startedAt: enumerateStartedAt,
                metadata: traceMetadata(
                    session: session,
                    extra: ["discovered_count": String(discoveredItems.count)]
                )
            )
        } catch {
            pause(session: &session, error: error)
            throw error
        }

        let itemsByResumeKey = discoveredItems.dictionaryByResumeKeyLastWins()
        var manifest: SessionManifest

        if let existingManifest {
            manifest = existingManifest
            session.totalItems = manifest.assets.count
            session.completedThumbnails = manifest.assets.filter { Self.fileExists(at: $0.thumbnailURL) }.count
            session.completedPreviews = manifest.assets.filter { Self.previewPhaseFinished(for: $0) }.count
            session.completedOriginals = manifest.assets.filter { Self.originalPhaseFinished(for: $0) }.count
            session.updatedAt = .now
            try ImportSessionStore.save(session)
            snapshot(.init(manifest: manifest, directory: projectDirectory, isFinal: false))
        } else {
            let manifestBuildStartedAt = ProcessInfo.processInfo.systemUptime
            session.phase = .preparingThumbnails
            session.totalItems = discoveredItems.count
            session.updatedAt = .now
            try ImportSessionStore.save(session)

            manifest = try await buildInitialManifest(
                session: &session,
                items: discoveredItems,
                adapter: adapter,
                progress: progress,
                connectionTracker: connectionTracker
            )

            try Self.saveManifest(manifest, in: projectDirectory)
            Self.traceMetric(
                "initial_manifest_built",
                startedAt: manifestBuildStartedAt,
                metadata: traceMetadata(
                    session: session,
                    extra: [
                        "asset_count": String(manifest.assets.count),
                        "group_count": String(manifest.groups.count),
                        "thumbnail_count": String(session.completedThumbnails)
                    ]
                )
            )
            snapshot(.init(manifest: manifest, directory: projectDirectory, isFinal: false))
        }

        session.phase = .copyingPreviews
        session.updatedAt = .now
        try ImportSessionStore.save(session)

        let previewCopyStartedAt = ProcessInfo.processInfo.systemUptime
        try await copyPreviewAssets(
            in: &manifest,
            itemsByResumeKey: itemsByResumeKey,
            adapter: adapter,
            session: &session,
            projectRoot: projectDirectory,
            progress: progress,
            connectionTracker: connectionTracker
        )
        Self.traceMetric(
            "preview_copy_completed",
            startedAt: previewCopyStartedAt,
            metadata: traceMetadata(
                session: session,
                extra: [
                    "asset_count": String(manifest.assets.count),
                    "completed_previews": String(session.completedPreviews)
                ]
            )
        )
        try Self.saveManifest(manifest, in: projectDirectory)
        snapshot(.init(manifest: manifest, directory: projectDirectory, isFinal: false))

        session.phase = .copyingOriginals
        session.updatedAt = .now
        try ImportSessionStore.save(session)

        let originalCopyStartedAt = ProcessInfo.processInfo.systemUptime
        try await copyOriginalAssets(
            in: &manifest,
            itemsByResumeKey: itemsByResumeKey,
            adapter: adapter,
            session: &session,
            projectRoot: projectDirectory,
            progress: progress,
            connectionTracker: connectionTracker
        )
        Self.traceMetric(
            "original_copy_completed",
            startedAt: originalCopyStartedAt,
            metadata: traceMetadata(
                session: session,
                extra: [
                    "asset_count": String(manifest.assets.count),
                    "completed_originals": String(session.completedOriginals)
                ]
            )
        )

        session.phase = .finalizing
        session.updatedAt = .now
        try ImportSessionStore.save(session)
        progress(.init(phase: .finalizing, completed: manifest.assets.count, total: max(manifest.assets.count, 1), currentItemName: nil))

        let groupingStartedAt = ProcessInfo.processInfo.systemUptime
        manifest.groups = await groupingEngine.makeGroups(from: manifest.assets, resolvesLocationNames: false)
        Self.traceMetric(
            "import_grouping_completed",
            startedAt: groupingStartedAt,
            metadata: traceMetadata(
                session: session,
                extra: [
                    "asset_count": String(manifest.assets.count),
                    "group_count": String(manifest.groups.count)
                ]
            )
        )
        var topSession = manifest.session
        var historySession = session
        historySession.status = .completed
        historySession.completedAt = .now
        historySession.importedAssetIDs = manifest.assets.map(\.id)
        historySession.projectDirectory = nil
        historySession.projectName = nil
        topSession.importSessions.append(historySession)
        topSession.updatedAt = .now
        manifest.session = topSession

        try Self.saveManifest(manifest, in: projectDirectory)
        snapshot(.init(manifest: manifest, directory: projectDirectory, isFinal: true))

        session.status = .completed
        session.updatedAt = .now
        let importedDirectory = projectDirectory
        try ImportSessionStore.delete(session)
        Self.logger.log("Imported \(manifest.assets.count) assets into \(importedDirectory.path, privacy: .public)")
        Self.traceMetric(
            "import_run_completed",
            startedAt: importStartedAt,
            metadata: traceMetadata(
                session: session,
                extra: [
                    "asset_count": String(manifest.assets.count),
                    "group_count": String(manifest.groups.count),
                    "project_directory": importedDirectory.lastPathComponent
                ]
            )
        )

        return ImportedProject(manifest: manifest, directory: importedDirectory)
    }

    private func buildInitialManifest(
        session: inout ImportSession,
        items: [DiscoveredItem],
        adapter: any ImportSourceAdapter,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        connectionTracker: ImportConnectionTracker
    ) async throws -> SessionManifest {
        guard let projectDir = session.projectDirectory else {
            throw LumaError.importFailed("导入会话缺少项目目录。")
        }
        var assets: [MediaAsset] = []
        assets.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            try await connectionTracker.ensureConnected()
            let assetID = UUID()
            let thumbnailURL = projectDir
                .appendingPathComponent("thumbnails", isDirectory: true)
                .appendingPathComponent("\(assetID.uuidString).png")

            if let thumbnail = await adapter.fetchThumbnail(item) {
                try? Self.writeThumbnail(thumbnail, to: thumbnailURL)
            }
            try await connectionTracker.ensureConnected()

            let previewURL = Self.destinationURL(
                for: item.previewFile,
                assetID: assetID,
                baseName: item.baseName,
                projectDirectory: projectDir,
                subdirectory: "preview"
            )
            let rawURL = Self.destinationURL(
                for: item.rawFile,
                assetID: assetID,
                baseName: item.baseName,
                projectDirectory: projectDir,
                subdirectory: "raw"
            )
            let auxiliaryURL = Self.destinationURL(
                for: item.auxiliaryFile,
                assetID: assetID,
                baseName: item.baseName,
                projectDirectory: projectDir,
                subdirectory: "auxiliary"
            )

            let importState: ImportState = Self.fileExists(at: thumbnailURL) ? .thumbnailReady : .discovered

            assets.append(
                MediaAsset(
                    id: assetID,
                    importResumeKey: item.resumeKey,
                    baseName: item.baseName,
                    source: item.source,
                    previewURL: previewURL,
                    rawURL: rawURL,
                    livePhotoVideoURL: auxiliaryURL,
                    depthData: item.depthData,
                    thumbnailURL: thumbnailURL,
                    metadata: item.metadata,
                    mediaType: item.mediaType,
                    importState: importState,
                    aiScore: nil,
                    editSuggestions: nil,
                    userDecision: .pending,
                    userRating: nil,
                    issues: []
                )
            )

            session.completedThumbnails = index + 1
            session.updatedAt = .now
            try ImportSessionStore.save(session)
            progress(
                .init(
                    phase: .preparingThumbnails,
                    completed: index + 1,
                    total: max(items.count, 1),
                    currentItemName: item.baseName
                )
            )
        }

        let manifestID = UUID()
        return SessionManifest(
            id: manifestID,
            name: session.displayProjectName,
            createdAt: session.createdAt,
            assets: assets,
            groups: []
        )
    }

    private func copyPreviewAssets(
        in manifest: inout SessionManifest,
        itemsByResumeKey: [String: DiscoveredItem],
        adapter: any ImportSourceAdapter,
        session: inout ImportSession,
        projectRoot: URL,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        connectionTracker: ImportConnectionTracker
    ) async throws {
        for index in manifest.assets.indices {
            let asset = manifest.assets[index]
            let isDone = Self.previewPhaseFinished(for: asset)
            if !isDone {
                try await connectionTracker.ensureConnected()
                guard let item = itemsByResumeKey[asset.importResumeKey] else {
                    let error = LumaError.importFailed("找不到 \(asset.baseName) 的导入来源，无法继续预览图拷贝。")
                    pause(session: &session, error: error)
                    throw error
                }

                do {
                    if let previewURL = asset.previewURL, !Self.fileExists(at: previewURL) {
                        try await adapter.copyPreview(item, to: previewURL.appendingPathExtension("importing"))
                        try Self.finishAtomicCopy(at: previewURL)
                    }
                    try await connectionTracker.ensureConnected()
                } catch {
                    pause(session: &session, error: error)
                    throw LumaError.importFailed("\(session.source.displayName) 导入已暂停：\(error.localizedDescription)")
                }

                manifest.assets[index].importState = Self.originalPhaseFinished(for: manifest.assets[index]) ? .complete : .previewCopied
                try Self.saveManifest(manifest, in: projectRoot)
            }

            session.completedPreviews = index + 1
            session.updatedAt = .now
            try ImportSessionStore.save(session)
            progress(
                .init(
                    phase: .copyingPreviews,
                    completed: session.completedPreviews,
                    total: max(manifest.assets.count, 1),
                    currentItemName: asset.baseName
                )
            )
        }
    }

    private func copyOriginalAssets(
        in manifest: inout SessionManifest,
        itemsByResumeKey: [String: DiscoveredItem],
        adapter: any ImportSourceAdapter,
        session: inout ImportSession,
        projectRoot: URL,
        progress: @escaping @Sendable (ImportProgress) -> Void,
        connectionTracker: ImportConnectionTracker
    ) async throws {
        for index in manifest.assets.indices {
            let asset = manifest.assets[index]
            let isDone = Self.originalPhaseFinished(for: asset)
            if !isDone {
                try await connectionTracker.ensureConnected()
                guard let item = itemsByResumeKey[asset.importResumeKey] else {
                    let error = LumaError.importFailed("找不到 \(asset.baseName) 的导入来源，无法继续原图拷贝。")
                    pause(session: &session, error: error)
                    throw error
                }

                do {
                    if let rawURL = asset.rawURL, !Self.fileExists(at: rawURL) {
                        try await adapter.copyOriginal(item, to: rawURL.appendingPathExtension("importing"))
                        try Self.finishAtomicCopy(at: rawURL)
                    }
                    if let auxiliaryURL = asset.livePhotoVideoURL, !Self.fileExists(at: auxiliaryURL) {
                        try await adapter.copyAuxiliary(item, to: auxiliaryURL.appendingPathExtension("importing"))
                        try Self.finishAtomicCopy(at: auxiliaryURL)
                    }
                    try await connectionTracker.ensureConnected()
                } catch {
                    pause(session: &session, error: error)
                    throw LumaError.importFailed("\(session.source.displayName) 导入已暂停：\(error.localizedDescription)")
                }

                manifest.assets[index].importState = Self.originalPhaseFinished(for: manifest.assets[index]) ? .complete : .rawCopied
                try Self.saveManifest(manifest, in: projectRoot)
            }

            session.completedOriginals = index + 1
            session.updatedAt = .now
            try ImportSessionStore.save(session)
            progress(
                .init(
                    phase: .copyingOriginals,
                    completed: session.completedOriginals,
                    total: max(manifest.assets.count, 1),
                    currentItemName: asset.baseName
                )
            )
        }
    }

    private func pause(session: inout ImportSession, error: Error) {
        session.status = .paused
        session.phase = .paused
        session.lastError = error.localizedDescription
        session.updatedAt = .now
        try? ImportSessionStore.save(session)
        let sourceName = session.source.displayName
        let metadata = traceMetadata(session: session, extra: ["message": error.localizedDescription])
        Self.logger.error("Import paused for \(sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        Self.traceError(
            "import_paused",
            metadata: metadata
        )
    }

    private func makeAdapter(for source: ImportSourceDescriptor) -> any ImportSourceAdapter {
        switch source {
        case .folder(let path, _):
            return FolderAdapter(rootFolder: URL(filePath: path))
        case .sdCard(let volumePath, _):
            return SDCardAdapter(volumeURL: URL(filePath: volumePath))
        case .iPhone(let deviceID, let deviceName):
            return iPhoneAdapter(deviceID: deviceID, deviceName: deviceName)
        case .photosLibrary(_, let limit, _):
            return PhotosLibraryAdapter(limit: limit)
        }
    }

    private static func destinationURL(
        for sourceURL: URL?,
        assetID: UUID,
        baseName: String,
        projectDirectory: URL,
        subdirectory: String
    ) -> URL? {
        guard let sourceURL else { return nil }
        let safeBaseName = AppDirectories.sanitizePathComponent(baseName)
        let pathExtension = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        return projectDirectory
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent("\(safeBaseName)_\(assetID.uuidString.prefix(8)).\(pathExtension)")
    }

    private static func fileExists(at url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func previewPhaseFinished(for asset: MediaAsset) -> Bool {
        asset.previewURL == nil || fileExists(at: asset.previewURL)
    }

    private static func originalPhaseFinished(for asset: MediaAsset) -> Bool {
        let rawReady = asset.rawURL == nil || fileExists(at: asset.rawURL)
        let auxiliaryReady = asset.livePhotoVideoURL == nil || fileExists(at: asset.livePhotoVideoURL)
        return rawReady && auxiliaryReady
    }

    private static func finishAtomicCopy(at destination: URL) throws {
        let fileManager = FileManager.default
        let temporaryDestination = destination.appendingPathExtension("importing")
        guard fileManager.fileExists(atPath: temporaryDestination.path) else { return }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryDestination, to: destination)
    }

    private static func writeThumbnail(_ image: CGImage, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw LumaError.persistenceFailed("无法创建缩略图缓存。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LumaError.persistenceFailed("无法写入缩略图缓存。")
        }
    }

    private static func saveManifest(_ manifest: SessionManifest, in directory: URL) throws {
        let manifestData = try JSONEncoder.lumaEncoder.encode(manifest)
        try manifestData.write(to: AppDirectories.manifestURL(in: directory), options: [.atomic])
    }

    private static func loadManifest(from directory: URL) throws -> SessionManifest {
        let data = try Data(contentsOf: AppDirectories.manifestURL(in: directory))
        return try JSONDecoder.lumaDecoder.decode(SessionManifest.self, from: data)
    }

    private static func traceEvent(_ name: String, metadata: [String: String]) {
        RuntimeTrace.event(name, category: "import", metadata: metadata)
    }

    private static func traceMetric(_ name: String, startedAt: TimeInterval, metadata: [String: String]) {
        var combined = metadata
        combined["duration_ms"] = durationString(since: startedAt)
        RuntimeTrace.metric(name, category: "import", metadata: combined)
    }

    private static func traceError(_ name: String, metadata: [String: String]) {
        RuntimeTrace.error(name, category: "import", metadata: metadata)
    }

    private func traceMetadata(session: ImportSession, extra: [String: String] = [:]) -> [String: String] {
        Self.traceMetadata(session: session, extra: extra)
    }

    private static func traceMetadata(session: ImportSession, extra: [String: String] = [:]) -> [String: String] {
        var metadata: [String: String] = [
            "session_id": session.id.uuidString,
            "source_kind": sourceKind(session.source),
            "source_name": session.source.displayName,
            "phase": session.phase.rawValue,
            "project_name": session.displayProjectName,
            "project_directory": session.projectDirectory?.lastPathComponent ?? "none",
            "total_items": String(session.totalItems),
            "completed_thumbnails": String(session.completedThumbnails),
            "completed_previews": String(session.completedPreviews),
            "completed_originals": String(session.completedOriginals)
        ]
        extra.forEach { metadata[$0.key] = $0.value }
        return metadata
    }

    private static func durationString(since startedAt: TimeInterval) -> String {
        String(format: "%.2f", max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
    }

    private static func sourceKind(_ source: ImportSourceDescriptor) -> String {
        switch source {
        case .folder:
            return "folder"
        case .sdCard:
            return "sd_card"
        case .iPhone:
            return "iphone"
        case .photosLibrary:
            return "photos_library"
        }
    }

    @MainActor
    private func chooseRecentPhotosLimit() throws -> Int {
        let alert = NSAlert()
        alert.messageText = "从 Mac · 照片 App 导入"
        alert.informativeText = "仅读取本地已缓存的照片，不会触发 iCloud 下载。请选择要导入的最近照片数量。"
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        let options: [Int] = [100, 200, 500, 1000, 2000]
        for value in options {
            popup.addItem(withTitle: "最近 \(value) 张")
        }
        popup.selectItem(at: 1)
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            throw LumaError.userCancelled
        }
        return options[popup.indexOfSelectedItem]
    }

    @MainActor
    private func chooseIPhoneDevice(from devices: [ConnectedAppleMobileDevice]) throws -> ConnectedAppleMobileDevice {
        guard !devices.isEmpty else {
            throw LumaError.unsupported("没有可导入的 iPhone 设备。")
        }

        if devices.count == 1 {
            return devices[0]
        }

        let alert = NSAlert()
        alert.messageText = "选择 iPhone 设备"
        alert.informativeText = "检测到多个可导入的 Apple 移动设备。"
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        for device in devices {
            popup.addItem(withTitle: "\(device.name) · \(device.productKind)")
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            throw LumaError.userCancelled
        }

        return devices[popup.indexOfSelectedItem]
    }
}

extension JSONEncoder {
    static var lumaEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
