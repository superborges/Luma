import DiskArbitration
import Foundation

/// DiskArbitration 事件驱动的可移除磁盘监控。
///
/// 替换轮询 `/Volumes/` 的方式，通过 `DARegisterDiskAppearedCallback` /
/// `DARegisterDiskDisappearedCallback` 实时获取挂载/卸载事件。
/// 仅关注含 DCIM 目录的可移除卷（SD 卡 / 相机存储）。
@MainActor
final class DiskArbitrationMonitor {

    struct MountedVolume: Hashable, Sendable {
        let volumePath: String
        let displayName: String
    }

    private var session: DASession?
    private let callbackQueue = DispatchQueue(label: "com.luma.disk-arbitration", qos: .utility)

    /// 当前挂载中的 SD 卡卷。
    private(set) var mountedVolumes: [MountedVolume] = []

    private var onChanged: (([MountedVolume]) -> Void)?

    /// C 回调通过此对象安全引用 monitor；weak 确保 monitor 已释放时回调空转而非 UB。
    private var contextBox: CallbackContextBox?

    /// 启动监控。每当可移除卷列表变化时调用 `onChange`。
    func start(onChange: @escaping @Sendable ([MountedVolume]) -> Void) {
        stop()
        self.onChanged = onChange

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            RuntimeTrace.event("da_session_create_failed", category: "import")
            fallbackToPolling(onChange: onChange)
            return
        }
        self.session = session

        DASessionSetDispatchQueue(session, callbackQueue)

        let box = CallbackContextBox(monitor: self)
        self.contextBox = box
        let context = Unmanaged.passRetained(box).toOpaque()

        let matching: CFDictionary = [
            kDADiskDescriptionMediaRemovableKey as String: true,
            kDADiskDescriptionVolumeMountableKey as String: true
        ] as NSDictionary

        DARegisterDiskAppearedCallback(session, matching, { _, ctx in
            guard let ctx else { return }
            let box = Unmanaged<CallbackContextBox>.fromOpaque(ctx).takeUnretainedValue()
            box.notifyChange()
        }, context)

        DARegisterDiskDisappearedCallback(session, matching, { _, ctx in
            guard let ctx else { return }
            let box = Unmanaged<CallbackContextBox>.fromOpaque(ctx).takeUnretainedValue()
            box.notifyChange()
        }, context)

        refreshMountedVolumes()
    }

    func stop() {
        if let session {
            DASessionSetDispatchQueue(session, nil)
        }
        session = nil
        onChanged = nil
        mountedVolumes = []
        if let contextBox {
            Unmanaged.passUnretained(contextBox).release()
            self.contextBox = nil
        }
    }

    // MARK: - Internal

    fileprivate func refreshMountedVolumes() {
        let newVolumes = Self.scanSDCardVolumes()
        let changed = Set(newVolumes) != Set(mountedVolumes)
        mountedVolumes = newVolumes
        if changed {
            onChanged?(newVolumes)
        }
    }

    // MARK: - Volume scanning

    static func scanSDCardVolumes() -> [MountedVolume] {
        SDCardAdapter.availableVolumes().map { url in
            MountedVolume(
                volumePath: url.path,
                displayName: url.lastPathComponent
            )
        }
    }

    // MARK: - Fallback

    private func fallbackToPolling(onChange: @escaping @Sendable ([MountedVolume]) -> Void) {
        Task { @MainActor [weak self] in
            while let self, self.onChanged != nil {
                self.refreshMountedVolumes()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

// MARK: - Callback context

/// DA 回调在 `callbackQueue` 上触发；通过 `weak` 引用回 MainActor 上的 monitor，
/// 避免 `stop()` 后 DA 队列残留回调引用已释放对象。
private final class CallbackContextBox: @unchecked Sendable {
    weak var monitor: DiskArbitrationMonitor?

    init(monitor: DiskArbitrationMonitor) {
        self.monitor = monitor
    }

    func notifyChange() {
        Task { @MainActor [weak self] in
            self?.monitor?.refreshMountedVolumes()
        }
    }
}
