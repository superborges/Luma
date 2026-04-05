import Foundation

@MainActor
final class ImportSourceMonitor {
    private let detectSourcesImpl: @Sendable () async -> [ImportSourceDescriptor]
    private var timer: Timer?
    private var knownSourceIDs: Set<String> = []
    private var isPolling = false

    init(detectSources: (@Sendable () async -> [ImportSourceDescriptor])? = nil) {
        self.detectSourcesImpl = detectSources ?? { await Self.detectSources() }
    }

    func start(onDetected: @escaping @Sendable (ImportSourceDescriptor) -> Void) {
        guard timer == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            let initialSources = await detectSourcesImpl()
            knownSourceIDs = Set(initialSources.map { $0.stableID })

            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.poll(onDetected: onDetected)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        knownSourceIDs.removeAll()
        isPolling = false
    }

    private func poll(onDetected: @escaping @Sendable (ImportSourceDescriptor) -> Void) {
        guard !isPolling else { return }
        isPolling = true

        Task { [weak self] in
            await self?.performPoll(onDetected: onDetected)
        }
    }

    func setKnownSourcesForTesting(_ sources: [ImportSourceDescriptor]) {
        knownSourceIDs = Set(sources.map { $0.stableID })
    }

    func pollNowForTesting(onDetected: @escaping @Sendable (ImportSourceDescriptor) -> Void) async {
        await performPoll(onDetected: onDetected)
    }

    private func performPoll(onDetected: @escaping @Sendable (ImportSourceDescriptor) -> Void) async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        let currentSources = await detectSourcesImpl()
        let currentIDs = Set(currentSources.map { $0.stableID })
        let newlyDetected = currentSources.filter { !knownSourceIDs.contains($0.stableID) }

        for source in newlyDetected {
            onDetected(source)
        }

        knownSourceIDs = currentIDs
    }

    static func detectSources() async -> [ImportSourceDescriptor] {
        let sdCards = SDCardAdapter.availableVolumes().map {
            ImportSourceDescriptor.sdCard(volumePath: $0.path, displayName: $0.lastPathComponent)
        }

        let devices = await iPhoneAdapter.availableDevices()
            .filter { !$0.isAccessRestricted }
            .map { device in
                ImportSourceDescriptor.iPhone(deviceID: device.id, deviceName: device.name)
            }

        return (sdCards + devices).sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
