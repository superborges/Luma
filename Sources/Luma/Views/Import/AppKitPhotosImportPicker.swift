import AppKit
import Foundation

/// PhotosImportPicker 的 AppKit 实现，**完全替代** SwiftUI 版本。
///
/// ## 为什么不用 SwiftUI（macOS 26 / SwiftUI 7.3 / Swift 6.2 / arm64e）
///
/// SwiftUI 版本的 `PhotosImportPickerView` 经历了 5 轮崩溃迭代，每修一条路径就崩在新路径上。
/// 详见 `KNOWN_ISSUES.md` Round 1–5。结论：该 SDK 组合下，只要 SwiftUI sheet 里的 view 在
/// sheet 显示后做异步 state mutation + body 重求值，就有概率撞 PAC failure，无法在 SwiftUI
/// 内规避。
///
/// ## AppKit 路径
///
/// 用 `NSAlert + accessoryView` 完全模态阻塞 main runloop。链路上：
/// - 没有 SwiftUI view body / ViewBuilder closure / @MainActor isolation thunk
/// - 没有 sheet container / sheet stacking timing
/// - 没有 Swift Concurrency Task 创建 + executor switch
/// - 控件全是 NSAlert 标准 control（NSSegmentedControl / NSPopUpButton / NSDatePicker），
///   稳定数十年。
///
/// 取舍：picker 上不再做"实时预估"。改为：用户选完点继续 → 异步估算 → 再弹一个 NSAlert
/// 二次确认（"将导入 X 张约 Y MB，确认？"）→ 才真正触发导入。这是更稳的两步式流程，反而
/// 比单 sheet 内实时刷新更不容易误操作。
@MainActor
enum AppKitPhotosImportPicker {
    /// 时间预设的固定段（自定义除外，单独处理）。
    private enum DatePresetTab: Int, CaseIterable {
        case last7
        case last30
        case last90
        case allTime
        case custom

        var label: String {
            switch self {
            case .last7: return "最近 7 天"
            case .last30: return "最近 30 天"
            case .last90: return "最近 90 天"
            case .allTime: return "不限"
            case .custom: return "自定义"
            }
        }
    }

    private enum MediaTab: Int, CaseIterable {
        case all
        case staticOnly
        case liveOnly

        var filter: PhotosImportPlan.MediaTypeFilter {
            switch self {
            case .all: return .all
            case .staticOnly: return .staticOnly
            case .liveOnly: return .liveOnly
            }
        }

        static func index(for filter: PhotosImportPlan.MediaTypeFilter) -> Int {
            switch filter {
            case .all: return MediaTab.all.rawValue
            case .staticOnly: return MediaTab.staticOnly.rawValue
            case .liveOnly: return MediaTab.liveOnly.rawValue
            }
        }
    }

    private static let limitOptions: [Int] = [200, 500, 1000, 2000, 10_000]

    /// Modal 同步弹出 picker；阻塞 main runloop 直到用户点继续 / 取消。
    /// 必须在 main thread 调用（`@MainActor` 已经强制）。
    ///
    /// - Parameters:
    ///   - initialPlan: 默认值，UI 会回填到对应控件。
    ///   - userAlbums: 当前 PhotoKit 的用户自建相册（按修改时间倒序）。空数组时 popup 只显示智能相册。
    static func presentBlocking(
        initialPlan: PhotosImportPlan,
        userAlbums: [PhotosImportPlanner.UserAlbumOption]
    ) -> PhotosImportPickerOutcome {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "从照片 App 导入"
        alert.informativeText = "组合多个筛选条件用 AND 叠加。点「估算并继续」会先告诉你将导入多少张、占多少磁盘，再让你确认。"
        alert.addButton(withTitle: "估算并继续")
        alert.addButton(withTitle: "取消")

        // ── 时间区间 ────────────────────
        let dateSegmented = NSSegmentedControl(
            labels: DatePresetTab.allCases.map(\.label),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        dateSegmented.segmentStyle = .rounded
        let initialDateTab = Self.dateTab(for: initialPlan.datePreset)
        dateSegmented.selectedSegment = initialDateTab.rawValue

        let startPicker = NSDatePicker()
        startPicker.datePickerStyle = .textFieldAndStepper
        startPicker.datePickerElements = [.yearMonthDay]
        startPicker.controlSize = .small
        let endPicker = NSDatePicker()
        endPicker.datePickerStyle = .textFieldAndStepper
        endPicker.datePickerElements = [.yearMonthDay]
        endPicker.controlSize = .small

        let initialRange = Self.initialCustomRange(from: initialPlan.datePreset)
        startPicker.dateValue = initialRange.start
        endPicker.dateValue = initialRange.end

        let customRow = NSStackView(views: [
            NSTextField(labelWithString: "起"),
            startPicker,
            NSTextField(labelWithString: "至"),
            endPicker
        ])
        customRow.orientation = .horizontal
        customRow.alignment = .firstBaseline
        customRow.spacing = 6
        customRow.isHidden = (initialDateTab != .custom)

        let dateTarget = SegmentedToggleTarget { selectedIndex in
            let tab = DatePresetTab(rawValue: selectedIndex) ?? .allTime
            customRow.isHidden = (tab != .custom)
        }
        dateSegmented.target = dateTarget
        dateSegmented.action = #selector(SegmentedToggleTarget.segmentedChanged(_:))

        // ── 相册（智能相册 + 用户自建相册）─────
        let albumPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        Self.populateAlbumPopup(albumPopup, smart: PhotosImportPlanner.smartAlbums, user: userAlbums)
        Self.selectAlbum(in: albumPopup, plan: initialPlan)

        // ── 媒体类型 ──────────────────
        let mediaSegmented = NSSegmentedControl(
            labels: MediaTab.allCases.map { tab -> String in
                switch tab {
                case .all: return PhotosImportPlan.MediaTypeFilter.all.label
                case .staticOnly: return PhotosImportPlan.MediaTypeFilter.staticOnly.label
                case .liveOnly: return PhotosImportPlan.MediaTypeFilter.liveOnly.label
                }
            },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        mediaSegmented.segmentStyle = .rounded
        mediaSegmented.selectedSegment = MediaTab.index(for: initialPlan.mediaTypeFilter)

        // ── 上限 ───────────────────
        let limitSegmented = NSSegmentedControl(
            labels: limitOptions.map { "\($0)" },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        limitSegmented.segmentStyle = .rounded
        if let idx = limitOptions.firstIndex(of: initialPlan.limit) {
            limitSegmented.selectedSegment = idx
        } else {
            limitSegmented.selectedSegment = limitOptions.firstIndex(of: 500) ?? 1
        }

        // ── 去重 ───────────────────
        let dedupeCheckbox = NSButton(checkboxWithTitle: "跳过本项目已导入过的照片", target: nil, action: nil)
        dedupeCheckbox.state = initialPlan.dedupeAgainstCurrentProject ? .on : .off

        // ── 组装 stack ────────────────
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(labeledRow(title: "时间区间", control: dateSegmented, fullWidth: true))
        stack.addArrangedSubview(customRow)
        stack.addArrangedSubview(labeledRow(title: "相册", control: albumPopup, fullWidth: true))
        stack.addArrangedSubview(labeledRow(title: "媒体类型", control: mediaSegmented, fullWidth: true))
        stack.addArrangedSubview(labeledRow(title: "本次最多导入", control: limitSegmented, fullWidth: true))
        stack.addArrangedSubview(dedupeCheckbox)

        // accessoryView 需要明确 frame；520x340 经验值能容纳 6 行 + 自定义行展开。
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 340))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4)
        ])
        alert.accessoryView = container

        // dateTarget 必须存活到 modal 结束；NSSegmentedControl.target 是 weak。
        objc_setAssociatedObject(alert, &Self.assocKey, dateTarget, .OBJC_ASSOCIATION_RETAIN)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return .cancelled
        }

        // ── 解析结果 ──────────────────
        let pickedDateTab = DatePresetTab(rawValue: dateSegmented.selectedSegment) ?? .last30
        let pickedDatePreset: PhotosImportPlan.DatePreset
        switch pickedDateTab {
        case .last7: pickedDatePreset = .last7
        case .last30: pickedDatePreset = .last30
        case .last90: pickedDatePreset = .last90
        case .allTime: pickedDatePreset = .allTime
        case .custom: pickedDatePreset = .custom(start: startPicker.dateValue, end: endPicker.dateValue)
        }

        let (pickedSmart, pickedUserAlbumID, pickedUserAlbumTitle) = Self.parseAlbum(from: albumPopup)
        let pickedMedia = MediaTab(rawValue: mediaSegmented.selectedSegment)?.filter ?? .all
        let pickedLimit = limitOptions[max(0, min(limitSegmented.selectedSegment, limitOptions.count - 1))]
        let pickedDedupe = (dedupeCheckbox.state == .on)

        let plan = PhotosImportPlan(
            id: initialPlan.id,
            datePreset: pickedDatePreset,
            smartAlbum: pickedSmart,
            userAlbumLocalIdentifier: pickedUserAlbumID,
            userAlbumTitle: pickedUserAlbumTitle,
            mediaTypeFilter: pickedMedia,
            limit: pickedLimit,
            dedupeAgainstCurrentProject: pickedDedupe
        )
        return .confirmed(plan)
    }

    /// 估算结果二次确认。返回 true 表示用户点了"导入"，false 表示返回修改 / 取消。
    static func presentEstimateConfirmation(estimate: PhotosImportPlanner.Estimate) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational

        let netCount = max(0, estimate.totalAssetCount - estimate.dedupedSkippedCount - estimate.cloudOnlyCount)

        if estimate.totalAssetCount == 0 {
            alert.messageText = "当前条件没有匹配到图片"
            alert.informativeText = "请调整时间区间 / 相册 / 媒体类型 / 上限后重试。"
            alert.addButton(withTitle: "返回修改")
            _ = alert.runModal()
            return false
        }

        if netCount == 0 {
            alert.messageText = "匹配到 \(estimate.totalAssetCount) 张，但全部会被跳过"
            var why: [String] = []
            if estimate.dedupedSkippedCount > 0 { why.append("\(estimate.dedupedSkippedCount) 张已存在本项目") }
            if estimate.cloudOnlyCount > 0 { why.append("约 \(estimate.cloudOnlyCount) 张仅在 iCloud") }
            alert.informativeText = why.joined(separator: "；") + "。请调整条件后重试。"
            alert.addButton(withTitle: "返回修改")
            _ = alert.runModal()
            return false
        }

        alert.messageText = "确认导入 \(netCount) 张？"
        var lines: [String] = []
        lines.append("匹配 \(estimate.totalAssetCount) 张")
        if estimate.dedupedSkippedCount > 0 {
            lines.append("· 跳过本项目已导入 \(estimate.dedupedSkippedCount) 张")
        }
        if estimate.cloudOnlyCount > 0 {
            lines.append("· 跳过仅在 iCloud 约 \(estimate.cloudOnlyCount) 张")
        }
        lines.append("实际导入约 \(netCount) 张 · 估算占用 \(estimate.prettyByteSize)")
        lines.append("（仅缩略 + 预览，原图导出时按需拉）")
        alert.informativeText = lines.joined(separator: "\n")

        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "返回修改")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - 辅助

    private static var assocKey: UInt8 = 0

    private static func dateTab(for preset: PhotosImportPlan.DatePreset) -> DatePresetTab {
        switch preset {
        case .last7: return .last7
        case .last30: return .last30
        case .last90: return .last90
        case .allTime: return .allTime
        case .custom: return .custom
        }
    }

    private static func initialCustomRange(from preset: PhotosImportPlan.DatePreset) -> (start: Date, end: Date) {
        let now = Date.now
        let calendar = Calendar.current
        switch preset {
        case .custom(let s, let e):
            return (s, e)
        default:
            // 默认给一个"过去 30 天 → 今天"的初值；用户切到"自定义"时立即可见。
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now)
        }
    }

    private static func populateAlbumPopup(
        _ popup: NSPopUpButton,
        smart: [PhotosImportPlanner.SmartAlbumOption],
        user: [PhotosImportPlanner.UserAlbumOption]
    ) {
        popup.removeAllItems()

        // (1) 全部图片
        popup.addItem(withTitle: "全部图片")
        popup.lastItem?.representedObject = AlbumChoice.all

        // (2) 智能相册分组
        if !smart.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: "智能相册", action: nil, keyEquivalent: "")
            header.isEnabled = false
            popup.menu?.addItem(header)
            for option in smart {
                let item = NSMenuItem(title: "  " + option.title, action: nil, keyEquivalent: "")
                item.representedObject = AlbumChoice.smart(option.id.rawValue)
                popup.menu?.addItem(item)
            }
        }

        // (3) 用户自建相册分组
        if !user.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: "我的相册", action: nil, keyEquivalent: "")
            header.isEnabled = false
            popup.menu?.addItem(header)
            for album in user {
                let item = NSMenuItem(title: "  " + album.title, action: nil, keyEquivalent: "")
                item.representedObject = AlbumChoice.user(id: album.id, title: album.title)
                popup.menu?.addItem(item)
            }
        }
    }

    private static func selectAlbum(in popup: NSPopUpButton, plan: PhotosImportPlan) {
        if let userID = plan.userAlbumLocalIdentifier,
           let item = popup.itemArray.first(where: {
               if case .user(let id, _) = $0.representedObject as? AlbumChoice { return id == userID }
               return false
           }) {
            popup.select(item)
            return
        }
        if let smart = plan.smartAlbum,
           let item = popup.itemArray.first(where: {
               if case .smart(let raw) = $0.representedObject as? AlbumChoice { return raw == smart.rawValue }
               return false
           }) {
            popup.select(item)
            return
        }
        popup.selectItem(at: 0)
    }

    private static func parseAlbum(from popup: NSPopUpButton)
        -> (smart: PhotosImportPlan.SmartAlbum?, userID: String?, userTitle: String?)
    {
        guard let choice = popup.selectedItem?.representedObject as? AlbumChoice else {
            return (nil, nil, nil)
        }
        switch choice {
        case .all:
            return (nil, nil, nil)
        case .smart(let raw):
            return (PhotosImportPlan.SmartAlbum(rawValue: raw), nil, nil)
        case .user(let id, let title):
            return (nil, id, title)
        }
    }

    private static func labeledRow(title: String, control: NSView, fullWidth: Bool) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor

        row.addArrangedSubview(label)
        row.addArrangedSubview(control)

        if fullWidth {
            control.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                control.trailingAnchor.constraint(equalTo: row.trailingAnchor)
            ])
        }
        return row
    }
}

/// NSPopUpButton item 的 `representedObject`：表达"用户在相册下拉里选了什么"。
private enum AlbumChoice {
    case all
    case smart(String)               // PhotosImportPlan.SmartAlbum.rawValue
    case user(id: String, title: String)
}

/// NSSegmentedControl 是 weak target；Swift 没法直接挂 closure，需要包成 NSObject。
///
/// **故意不标 `@MainActor`**：AppKit 在 main thread 通过 ObjC 调 `segmentedChanged(_:)`；
/// 给 ObjC 可见的类加 `@MainActor` 会让编译器在 `@objc` 方法 prologue 注入
/// `swift_task_isCurrentExecutorWithFlagsImpl` PAC 校验，在 macOS 26 / arm64e 下会撞
/// `swift_getObjectType(invalid_addr)` SIGSEGV（详见 `LumaApp.swift` 中的同样修复
/// 与 `KNOWN_ISSUES.md`）。
private final class SegmentedToggleTarget: NSObject {
    let onChange: (Int) -> Void
    init(onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
    }
    @objc func segmentedChanged(_ sender: NSSegmentedControl) {
        // 从 nonisolated context 访问 main-actor 隔离的 NSSegmentedControl 属性。
        // AppKit 在 main thread 触发该 selector，运行时已在 main actor 上，
        // 所以 assumeIsolated 永远不会 trap。
        let index = MainActor.assumeIsolated { sender.selectedSegment }
        onChange(index)
    }
}
