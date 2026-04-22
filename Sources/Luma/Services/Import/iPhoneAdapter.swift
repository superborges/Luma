import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import ImageCaptureCore

extension ICCameraDevice: @retroactive @unchecked Sendable {}

struct ConnectedAppleMobileDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let productKind: String
    let isAccessRestricted: Bool

    var displayTitle: String {
        if isAccessRestricted {
            return "\(name)（未解锁或未信任）"
        }
        return name
    }
}

struct iPhoneAdapter: ImportSourceAdapter {
    let deviceID: String
    let deviceName: String

    private let session: IPhoneImportSession

    init(deviceID: String, deviceName: String = "iPhone") {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.session = IPhoneImportSession(deviceID: deviceID, preferredName: deviceName)
    }

    var displayName: String {
        deviceName
    }

    var connectionState: AsyncStream<ConnectionState> {
        let monitoredDeviceID = deviceID
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                var previousState = await Self.detectConnectionState(for: monitoredDeviceID)
                continuation.yield(previousState)

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    let currentState = await Self.detectConnectionState(for: monitoredDeviceID)
                    if currentState != previousState {
                        continuation.yield(currentState)
                        previousState = currentState
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func availableDevices() async -> [ConnectedAppleMobileDevice] {
        // ImageCaptureCore 要求 ICDeviceBrowser 在主线程创建 / start；且并发两次 start
        // 会在系统框架里 objc_msgSend 崩（见 crash: Thread 6 + 10 同栈）。因此：
        // 1) @MainActor 跑整段 discovery；2) actor 串行化并发调用。
        let devices = await IPhoneDiscoverySerialGate.shared.discover()
        return devices
            .compactMap { device in
                guard let id = device.uuidString, !id.isEmpty else { return nil }
                let productKind = device.productKind ?? "Apple Device"
                let name = device.name ?? productKind
                return ConnectedAppleMobileDevice(
                    id: id,
                    name: name,
                    productKind: productKind,
                    isAccessRestricted: device.isAccessRestrictedAppleDevice
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func detectConnectionState(for deviceID: String) async -> ConnectionState {
        let devices = await availableDevices()
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            return .disconnected
        }
        return device.isAccessRestricted ? .unavailable : .connected
    }

    func enumerate() async throws -> [DiscoveredItem] {
        try await session.enumerateItems()
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        await session.thumbnail(for: item.previewFile ?? item.rawFile)
    }

    func copyPreview(_ item: DiscoveredItem, to destination: URL) async throws {
        try await session.download(from: item.previewFile, to: destination)
    }

    func copyOriginal(_ item: DiscoveredItem, to destination: URL) async throws {
        try await session.download(from: item.rawFile, to: destination)
    }

    func copyAuxiliary(_ item: DiscoveredItem, to destination: URL) async throws {
        try await session.download(from: item.auxiliaryFile, to: destination)
    }
}

private final class IPhoneImportSession {
    private enum RemoteAssetRole: String {
        case preview
        case raw
        case auxiliary
    }

    private let deviceID: String
    private let preferredName: String
    private var device: ICCameraDevice?
    private var remoteFiles: [String: ICCameraFile] = [:]

    init(deviceID: String, preferredName: String) {
        self.deviceID = deviceID
        self.preferredName = preferredName
    }

    deinit {
        device?.requestCloseSession(options: nil) { _ in }
    }

    func enumerateItems() async throws -> [DiscoveredItem] {
        let device = try await ensureDevice()
        let files = try await mediaFiles(for: device)
        remoteFiles = [:]

        let previewExtensions = Set(["jpg", "jpeg", "heic", "heif", "png"])
        let rawExtensions = Set(["dng", "arw", "cr3", "nef", "raf", "orf", "rw2"])
        let videoExtensions = Set(["mov"])

        let cameraFiles = files.filter { file in
            let ext = fileExtension(for: file)
            return previewExtensions.contains(ext) || rawExtensions.contains(ext) || videoExtensions.contains(ext)
        }

        var previewCandidates: [ICCameraFile] = []
        var rawsByKey: [String: [ICCameraFile]] = [:]
        var videosByKey: [String: [ICCameraFile]] = [:]

        for file in cameraFiles {
            let key = pairingKey(for: file)
            let ext = fileExtension(for: file)
            if videoExtensions.contains(ext) {
                videosByKey[key, default: []].append(file)
            } else if rawExtensions.contains(ext) || file.isRaw {
                rawsByKey[key, default: []].append(file)
            } else {
                previewCandidates.append(file)
            }
        }

        let sortedPreviews = previewCandidates.sorted(by: sortFiles)
        var consumedRaws = Set<String>()
        var consumedVideos = Set<String>()
        var items: [DiscoveredItem] = []

        for preview in sortedPreviews {
            let key = pairingKey(for: preview)
            let pairedRaw = preview.pairedRawImage ?? rawsByKey[key]?.first(where: { !consumedRaws.contains(fileIdentity(for: $0)) })
            let liveVideo = videosByKey[key]?.first(where: { !consumedVideos.contains(fileIdentity(for: $0)) })

            if let pairedRaw {
                consumedRaws.insert(fileIdentity(for: pairedRaw))
            }
            if let liveVideo {
                consumedVideos.insert(fileIdentity(for: liveVideo))
            }

            items.append(
                DiscoveredItem(
                    id: UUID(),
                    resumeKey: key,
                    baseName: baseName(for: preview),
                    source: .iPhone(deviceID: deviceID),
                    previewFile: register(preview, role: .preview),
                    rawFile: pairedRaw.map { register($0, role: .raw) },
                    auxiliaryFile: liveVideo.map { register($0, role: .auxiliary) },
                    depthData: false,
                    metadata: metadata(for: preview, fallback: pairedRaw, device: device),
                    mediaType: liveVideo == nil ? .photo : .livePhoto
                )
            )
        }

        let remainingRaws = rawsByKey.values
            .flatMap { $0 }
            .filter { !consumedRaws.contains(fileIdentity(for: $0)) }
            .sorted(by: sortFiles)

        for raw in remainingRaws {
            let key = pairingKey(for: raw)
            let liveVideo = videosByKey[key]?.first(where: { !consumedVideos.contains(fileIdentity(for: $0)) })
            if let liveVideo {
                consumedVideos.insert(fileIdentity(for: liveVideo))
            }

            items.append(
                DiscoveredItem(
                    id: UUID(),
                    resumeKey: key,
                    baseName: baseName(for: raw),
                    source: .iPhone(deviceID: deviceID),
                    previewFile: nil,
                    rawFile: register(raw, role: .raw),
                    auxiliaryFile: liveVideo.map { register($0, role: .auxiliary) },
                    depthData: false,
                    metadata: metadata(for: raw, fallback: nil, device: device),
                    mediaType: liveVideo == nil ? .photo : .livePhoto
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.metadata.captureDate == rhs.metadata.captureDate {
                return lhs.baseName.localizedCaseInsensitiveCompare(rhs.baseName) == .orderedAscending
            }
            return lhs.metadata.captureDate < rhs.metadata.captureDate
        }
    }

    func thumbnail(for referenceURL: URL?) async -> CGImage? {
        guard let file = remoteFile(for: referenceURL) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            file.requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: 400]) { data, _ in
                guard let data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    func download(from referenceURL: URL?, to destination: URL) async throws {
        guard let file = remoteFile(for: referenceURL) else { return }

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destination.deletingLastPathComponent(),
            .saveAsFilename: destination.lastPathComponent,
            .overwrite: true,
            .sidecarFiles: false,
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = file.requestDownload(options: options) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func ensureDevice() async throws -> ICCameraDevice {
        if let device {
            return device
        }

        let discovered = await IPhoneDeviceDiscovery().discoverDevices(timeout: .seconds(4))
        guard let device = discovered.first(where: { $0.uuidString == deviceID }) else {
            throw LumaError.unsupported("未检测到 \(preferredName)。请通过 USB 连接设备，并在手机上点击“信任此电脑”。")
        }
        if device.isAccessRestrictedAppleDevice {
            throw LumaError.unsupported("已检测到 \(preferredName)，但设备仍未解锁或未信任当前 Mac。")
        }

        try await openSession(for: device)
        if device.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue) {
            device.mediaPresentation = .originalAssets
        }

        self.device = device
        return device
    }

    private func openSession(for device: ICCameraDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            device.requestOpenSession(options: nil) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func mediaFiles(for device: ICCameraDevice) async throws -> [ICCameraFile] {
        var attempts = 0
        while attempts < 80 {
            let files = device.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
            if device.contentCatalogPercentCompleted >= 100 {
                return files
            }
            if !files.isEmpty, attempts >= 10 {
                return files
            }
            attempts += 1
            try await Task.sleep(for: .milliseconds(200))
        }

        let files = device.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
        if files.isEmpty {
            throw LumaError.unsupported("\(preferredName) 当前没有可导入的照片资源。")
        }
        return files
    }

    private func register(_ file: ICCameraFile, role: RemoteAssetRole) -> URL {
        let token = UUID().uuidString
        let filename = (file.originalFilename ?? file.name ?? "asset")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "asset"
        let reference = URL(string: "luma-iphone://\(deviceID)/\(role.rawValue)/\(token)/\(filename)")!
        remoteFiles[reference.absoluteString] = file
        return reference
    }

    private func remoteFile(for referenceURL: URL?) -> ICCameraFile? {
        guard let referenceURL else { return nil }
        return remoteFiles[referenceURL.absoluteString]
    }

    private func metadata(for file: ICCameraFile, fallback: ICCameraFile?, device: ICCameraDevice) -> EXIFData {
        let representative = fallback ?? file
        return EXIFData(
            captureDate: representative.exifCreationDate
                ?? representative.fileCreationDate
                ?? representative.creationDate
                ?? .now,
            gpsCoordinate: nil,
            focalLength: nil,
            aperture: nil,
            shutterSpeed: nil,
            iso: nil,
            cameraModel: device.name ?? device.productKind,
            lensModel: nil,
            imageWidth: max(0, representative.width),
            imageHeight: max(0, representative.height)
        )
    }

    private func pairingKey(for file: ICCameraFile) -> String {
        let candidates: [String] = [
            file.groupUUID,
            file.originatingAssetID,
            file.relatedUUID,
            baseName(for: file).lowercased(),
        ].compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return candidates.first ?? UUID().uuidString
    }

    private func sortFiles(_ lhs: ICCameraFile, _ rhs: ICCameraFile) -> Bool {
        let lhsDate = lhs.exifCreationDate ?? lhs.fileCreationDate ?? lhs.creationDate ?? .distantPast
        let rhsDate = rhs.exifCreationDate ?? rhs.fileCreationDate ?? rhs.creationDate ?? .distantPast

        if lhsDate == rhsDate {
            return baseName(for: lhs).localizedCaseInsensitiveCompare(baseName(for: rhs)) == .orderedAscending
        }
        return lhsDate < rhsDate
    }

    private func fileIdentity(for file: ICCameraFile) -> String {
        if let fingerprint = file.fingerprint, !fingerprint.isEmpty {
            return fingerprint
        }
        if let originalFilename = file.originalFilename, !originalFilename.isEmpty {
            return "\(originalFilename)#\(file.fileSize)#\(file.ptpObjectHandle)"
        }
        return "\(file.ptpObjectHandle)"
    }

    private func baseName(for file: ICCameraFile) -> String {
        let filename = file.originalFilename ?? file.name ?? "IMG_\(file.ptpObjectHandle)"
        return URL(filePath: filename).deletingPathExtension().lastPathComponent
    }

    private func fileExtension(for file: ICCameraFile) -> String {
        let filename = file.originalFilename ?? file.name ?? ""
        return URL(filePath: filename).pathExtension.lowercased()
    }
}

/// 串行化所有 `ICDeviceBrowser` 发现：避免 ImportSourceMonitor 与 ProjectStore 周期刷新并发
/// 各调一次 `availableDevices()` 时在框架内撞车。
private actor IPhoneDiscoverySerialGate {
    static let shared = IPhoneDiscoverySerialGate()

    func discover(timeout: Duration = .seconds(2)) async -> [ICCameraDevice] {
        await IPhoneDeviceDiscovery().discoverDevices(timeout: timeout)
    }
}

@MainActor
private final class IPhoneDeviceDiscovery: NSObject, ICDeviceBrowserDelegate {
    private var browser: ICDeviceBrowser?
    private var devices: [ICCameraDevice] = []
    private var continuation: CheckedContinuation<[ICCameraDevice], Never>?
    private var timeoutWorkItem: DispatchWorkItem?

    func discoverDevices(timeout: Duration = .seconds(2)) async -> [ICCameraDevice] {
        devices = []

        let browser = ICDeviceBrowser()
        self.browser = browser
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            browser.start()
            let components = timeout.components
            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
            let workItem = DispatchWorkItem { [weak self] in
                self?.finish()
            }
            timeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    /// ImageCapture 回调可能来自非主队列；用 `nonisolated` + 切回 MainActor，避免与 `start` 线程打架。
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        Task { @MainActor [weak self] in
            self?.handleDidAdd(browser: browser, device: device, moreComing: moreComing)
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor [weak self] in
            self?.handleDidRemove(browser: browser, device: device, moreGoing: moreGoing)
        }
    }

    nonisolated func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {
        Task { @MainActor [weak self] in
            self?.finish()
        }
    }

    private func handleDidAdd(browser: ICDeviceBrowser, device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice,
              Self.isSupportedAppleMobileDevice(camera) else {
            return
        }

        if !devices.contains(where: { $0.uuidString == camera.uuidString }) {
            devices.append(camera)
        }

        if !moreComing, browser.isBrowsing == false {
            finish()
        }
    }

    private func handleDidRemove(browser: ICDeviceBrowser, device: ICDevice, moreGoing: Bool) {
        guard let removedID = device.uuidString else { return }
        devices.removeAll { $0.uuidString == removedID }
        if !moreGoing, browser.isBrowsing == false {
            finish()
        }
    }

    private func finish() {
        guard let continuation else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        browser?.stop()
        browser?.delegate = nil
        browser = nil
        self.continuation = nil

        continuation.resume(
            returning: devices.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
        )
    }

    private static func isSupportedAppleMobileDevice(_ device: ICCameraDevice) -> Bool {
        let kind = (device.productKind ?? "").lowercased()
        if ["iphone", "ipad", "ipod"].contains(kind) {
            return true
        }

        let name = (device.name ?? "").lowercased()
        return name.contains("iphone") || name.contains("ipad") || name.contains("ipod")
    }
}
