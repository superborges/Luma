import AppKit
import Foundation

/// 照片导入月份选择器 — 按年翻页，纯 AppKit modal。
///
/// 每页最多 12 个月，用 ◀/▶ 切换年份，无滚动。
/// **不标 `@MainActor`**：避免 ObjC selector 回调 PAC 崩溃。
enum AppKitPhotosImportPicker {

    static func presentBlocking(
        monthlyStats: [PhotosImportPlanner.MonthStats]
    ) -> PhotosImportPickerOutcome {
        precondition(Thread.isMainThread)
        NSApp.activate(ignoringOtherApps: true)

        if monthlyStats.isEmpty {
            let empty = NSAlert()
            empty.alertStyle = .informational
            empty.messageText = "照片图库中没有找到照片"
            empty.informativeText = "请确认「照片」App 中有照片，且 Luma 已获得完整图库读取权限。"
            empty.addButton(withTitle: "好")
            empty.runModal()
            return .cancelled
        }

        let state = PickerState(allStats: monthlyStats)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "从照片 App 导入"
        alert.informativeText = "勾选要导入的月份。只读本地缓存，不触发 iCloud 下载。"
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")

        let container = buildAccessoryView(state: state)
        alert.accessoryView = container
        state.showCurrentYear()

        objc_setAssociatedObject(alert, &assocKey, state, .OBJC_ASSOCIATION_RETAIN)

        ImportPathBreadcrumb.mark("photos_month_picker_modal", [
            "month_count": String(monthlyStats.count),
            "year_count": String(state.years.count)
        ])
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            ImportPathBreadcrumb.mark("photos_month_picker_cancelled", [:])
            return .cancelled
        }

        let selectedMonths = state.selectedMonths()
        if selectedMonths.isEmpty {
            let noSel = NSAlert()
            noSel.alertStyle = .informational
            noSel.messageText = "未选择任何月份"
            noSel.informativeText = "请至少勾选一个月份后再点导入。"
            noSel.addButton(withTitle: "好")
            noSel.runModal()
            return .cancelled
        }

        let totalPhotos = state.selectedPhotoCount()
        ImportPathBreadcrumb.mark("photos_month_picker_confirmed", [
            "selected_months": String(selectedMonths.count),
            "total_photos": String(totalPhotos)
        ])

        let plan = PhotosImportPlan(
            id: UUID(),
            selectedMonths: selectedMonths,
            mediaTypeFilter: .all,
            dedupeAgainstCurrentProject: true
        )
        return .confirmed(plan)
    }

    // MARK: - Private

    private static var assocKey: UInt8 = 0

    private static func buildAccessoryView(state: PickerState) -> NSView {
        let width: CGFloat = 520
        let rowHeight: CGFloat = 28
        let maxRows = 12
        let pageHeight = CGFloat(maxRows) * rowHeight
        let navHeight: CGFloat = 32
        let summaryHeight: CGFloat = 24
        let totalHeight = navHeight + pageHeight + summaryHeight + 8

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))

        // Year navigation bar
        let prevBtn = NSButton(title: "◀", target: state, action: #selector(PickerState.prevYear(_:)))
        prevBtn.bezelStyle = .inline
        prevBtn.frame = NSRect(x: 8, y: totalHeight - navHeight, width: 44, height: 24)
        container.addSubview(prevBtn)
        state.prevButton = prevBtn

        let yearLabel = NSTextField(labelWithString: "")
        yearLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        yearLabel.alignment = .center
        yearLabel.frame = NSRect(x: 60, y: totalHeight - navHeight, width: width - 120, height: 24)
        container.addSubview(yearLabel)
        state.yearLabel = yearLabel

        let nextBtn = NSButton(title: "▶", target: state, action: #selector(PickerState.nextYear(_:)))
        nextBtn.bezelStyle = .inline
        nextBtn.frame = NSRect(x: width - 52, y: totalHeight - navHeight, width: 44, height: 24)
        container.addSubview(nextBtn)
        state.nextButton = nextBtn

        // Page area — one container per year, overlapping in the same position
        let pageOriginY = summaryHeight + 8
        let pageArea = FlippedPageView(frame: NSRect(x: 0, y: pageOriginY, width: width, height: pageHeight))
        container.addSubview(pageArea)

        let countColX: CGFloat = 150
        let tagColX: CGFloat = 330

        for year in state.years {
            let yearView = FlippedPageView(frame: NSRect(x: 0, y: 0, width: width, height: pageHeight))
            yearView.isHidden = true

            let months = state.statsByYear[year]!.sorted { $0.slot.month > $1.slot.month }
            for (row, stats) in months.enumerated() {
                let y = CGFloat(row) * rowHeight

                let cb = NSButton(checkboxWithTitle: stats.slot.label, target: state,
                                  action: #selector(PickerState.checkboxChanged(_:)))
                cb.font = .systemFont(ofSize: 13, weight: .medium)
                cb.frame = NSRect(x: 8, y: y, width: countColX - 8, height: rowHeight)
                yearView.addSubview(cb)
                state.register(checkbox: cb, for: stats)

                let countLabel = NSTextField(labelWithString: "\(stats.photoCount)张 · \(stats.prettyByteSize)")
                countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                countLabel.textColor = .secondaryLabelColor
                countLabel.frame = NSRect(x: countColX, y: y + 2, width: tagColX - countColX - 4, height: rowHeight)
                yearView.addSubview(countLabel)

                var tagText: String?
                var tagColor: NSColor = .secondaryLabelColor
                if stats.isLargeMonth && stats.hasPreviousImport {
                    tagText = "⚠ 量大 · 已导入\(stats.previouslyImportedCount)张"
                    tagColor = .systemOrange
                } else if stats.isLargeMonth {
                    tagText = "⚠ 数量较多"
                    tagColor = .systemOrange
                } else if stats.hasPreviousImport {
                    tagText = "⚠ 已导入\(stats.previouslyImportedCount)张"
                    tagColor = .systemBrown
                }
                if let tagText {
                    let tag = NSTextField(labelWithString: tagText)
                    tag.font = .systemFont(ofSize: 11)
                    tag.textColor = tagColor
                    tag.frame = NSRect(x: tagColX, y: y + 3, width: width - tagColX - 8, height: rowHeight)
                    yearView.addSubview(tag)
                }
            }

            pageArea.addSubview(yearView)
            state.yearViews[year] = yearView
        }

        // Summary label
        let summaryLabel = NSTextField(labelWithString: "已选：0个月 · 0张")
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.frame = NSRect(x: 8, y: 0, width: width - 16, height: summaryHeight)
        container.addSubview(summaryLabel)
        state.summaryLabel = summaryLabel

        return container
    }
}

/// 管理翻页状态和所有 checkbox 引用。故意不标 `@MainActor`。
private final class PickerState: NSObject {
    let years: [Int]
    let statsByYear: [Int: [PhotosImportPlanner.MonthStats]]
    private(set) var currentYearIndex: Int = 0

    var yearLabel: NSTextField!
    var prevButton: NSButton!
    var nextButton: NSButton!
    var summaryLabel: NSTextField!
    var yearViews: [Int: NSView] = [:]

    private var checkboxMap: [(checkbox: NSButton, stats: PhotosImportPlanner.MonthStats)] = []

    init(allStats: [PhotosImportPlanner.MonthStats]) {
        var byYear: [Int: [PhotosImportPlanner.MonthStats]] = [:]
        for s in allStats { byYear[s.slot.year, default: []].append(s) }
        self.statsByYear = byYear
        self.years = byYear.keys.sorted(by: >)
    }

    func register(checkbox: NSButton, for stats: PhotosImportPlanner.MonthStats) {
        checkboxMap.append((checkbox, stats))
    }

    func selectedMonths() -> [PhotosImportPlan.MonthSlot] {
        checkboxMap.compactMap { $0.checkbox.state == .on ? $0.stats.slot : nil }
    }

    func selectedPhotoCount() -> Int {
        checkboxMap.reduce(0) { $0 + ($1.checkbox.state == .on ? $1.stats.photoCount : 0) }
    }

    func showCurrentYear() {
        guard !years.isEmpty else { return }
        let year = years[currentYearIndex]
        yearLabel.stringValue = "\(year)年"
        prevButton.isEnabled = currentYearIndex < years.count - 1
        nextButton.isEnabled = currentYearIndex > 0

        for (y, view) in yearViews {
            view.isHidden = (y != year)
        }
    }

    @objc func prevYear(_ sender: Any) {
        guard currentYearIndex < years.count - 1 else { return }
        currentYearIndex += 1
        showCurrentYear()
    }

    @objc func nextYear(_ sender: Any) {
        guard currentYearIndex > 0 else { return }
        currentYearIndex -= 1
        showCurrentYear()
    }

    @objc func checkboxChanged(_ sender: NSButton) {
        updateSummary()
    }

    private func updateSummary() {
        var monthCount = 0
        var photoCount = 0
        var totalBytes: Int64 = 0
        for (cb, stats) in checkboxMap where cb.state == .on {
            monthCount += 1
            photoCount += stats.photoCount
            totalBytes += stats.estimatedBytes
        }
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        summaryLabel.stringValue = "已选：\(monthCount)个月 · \(photoCount)张 · \(sizeStr)"
    }
}

private final class FlippedPageView: NSView {
    override var isFlipped: Bool { true }
}
