import AppKit
import Foundation

/// **调试路径**：从「照片」导入时**只问张数**——无日期/相册/媒体类型/去重 UI、无「估算+二次确认」模态。
/// 用最小 NSAlert + NSPopUpButton（与 `ImportManager.chooseRecentPhotosLimit` 同形），避免
/// `NSSegmentedControl` + ObjC target 等附加回调链，便于和崩溃现场对照。
enum AppKitPhotosCountOnlyPicker {
    private static let options: [Int] = [100, 200, 500, 1000, 2000, 10_000]

    /// 必须在主线程调用。`nil` = 用户取消。
    static func presentBlocking() -> Int? {
        precondition(Thread.isMainThread)
        let alert = NSAlert()
        alert.messageText = "从「照片」导入（仅数量·调试）"
        alert.informativeText = "从图库按时间倒序取前 N 张；全部时间、不选相册/类型。只读本地缓存，不拉 iCloud。"
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for v in options {
            popup.addItem(withTitle: "最近 \(v) 张")
        }
        popup.selectItem(at: 2)

        alert.accessoryView = popup

        ImportPathBreadcrumb.mark("photos_count_only_picker", ["count_options": String(options.count)])
        guard alert.runModal() == .alertFirstButtonReturn else {
            ImportPathBreadcrumb.mark("photos_count_only_cancel", [:])
            return nil
        }
        let idx = min(max(0, popup.indexOfSelectedItem), options.count - 1)
        let n = options[idx]
        ImportPathBreadcrumb.mark("photos_count_only_ok", ["limit": String(n)])
        return n
    }
}
