import Foundation
import SwiftUI

/// 注册中的一个 UI 元素的快照信息。
///
/// UIRegistry 是 Luma 的 UI 定位系统：每个用 `.lumaTrack(id:)` 修饰的 SwiftUI 节点会把自己的
/// id、kind、当前 frame（在主窗口的 LumaWindow 命名坐标空间内）以及一些 metadata 注册到这里。
///
/// 用途：
/// - debug：`Cmd+Shift+D` 一把把所有元素 id+frame 写入 trace，方便事后还原"用户那一瞬间看到的是什么"。
/// - log 关联：`UITrace.tap(id:)` 自动从 registry 取 frame 拼到 trace metadata，trace 里能直接看到坐标。
/// - Inspector Overlay：`Cmd+Shift+U` 打开的可视化 overlay 直接按这些 frame 画红框，不用截图就能对齐。
/// - testing：测试代码可以直接用 `UIRegistry().info(for:)` 查 frame 做断言。
struct UIElementInfo: Equatable {
    let id: String
    let kind: String
    let frameInWindow: CGRect
    let metadata: [String: String]
    let firstSeenAt: Date
    let lastSeenAt: Date
}

@MainActor
@Observable
final class UIRegistry {
    /// 全局共享实例（被 `lumaTrack` 修饰符使用）。测试代码可以构造独立实例。
    static let shared = UIRegistry()

    private(set) var elements: [String: UIElementInfo] = [:]

    /// Inspector Overlay 开关。`true` 时 `ContentView` 会在最外层叠一层
    /// `LumaInspectorOverlay`，把所有注册元素的 frame 在窗口坐标系里画出来，同时
    /// 提供「复制 textual report 到剪贴板」按钮，实现**不用截图**的 UI 对齐。
    /// 默认关闭，只在需要 debug 时打开（`Cmd+Shift+U` 或性能诊断面板里手动切换）。
    var isInspectorEnabled: Bool = false

    init() {}

    /// 注册或更新一个 UI 元素。
    /// - 第一次注册：firstSeenAt = lastSeenAt = now。
    /// - 同 id 重复注册（frame 变了 / metadata 变了）：保留 firstSeenAt，更新其它字段。
    func register(
        id: String,
        kind: String,
        frame: CGRect,
        metadata: [String: String]
    ) {
        let now = Date.now
        if let existing = elements[id] {
            elements[id] = UIElementInfo(
                id: id,
                kind: kind,
                frameInWindow: frame,
                metadata: metadata,
                firstSeenAt: existing.firstSeenAt,
                lastSeenAt: now
            )
        } else {
            elements[id] = UIElementInfo(
                id: id,
                kind: kind,
                frameInWindow: frame,
                metadata: metadata,
                firstSeenAt: now,
                lastSeenAt: now
            )
        }
    }

    func unregister(id: String) {
        elements.removeValue(forKey: id)
    }

    func info(for id: String) -> UIElementInfo? {
        elements[id]
    }

    /// 按 id 字典序返回当前所有元素。`Cmd+Shift+D` dump 时也用这个顺序，便于 diff。
    func sortedElements() -> [UIElementInfo] {
        elements.values.sorted { $0.id < $1.id }
    }

    /// 翻转 Inspector Overlay 开关，并发一条 trace 事件方便事后对时间戳。
    /// - Parameter reason: 调用来源（"shortcut_cmd_shift_u" / "diagnostics_panel" / ...），写到 trace metadata。
    /// - Returns: 翻转后的新状态。
    @discardableResult
    func toggleInspector(reason: String) -> Bool {
        isInspectorEnabled.toggle()
        RuntimeTrace.event(
            "ui_inspector_toggled",
            category: "ui",
            metadata: [
                "enabled": isInspectorEnabled ? "true" : "false",
                "reason": reason,
                "element_count": String(elements.count)
            ]
        )
        return isInspectorEnabled
    }

    /// 把当前 registry 的所有元素格式化成**纯文本报告**，适合一键复制到剪贴板粘贴给
    /// AI / 队友，作为「不用截图」的 UI 对齐方式。
    ///
    /// 格式（固定列宽、等宽友好）：
    /// ```
    /// # Luma UI Inspector — 2026-04-21 10:30:12 (42 elements)
    /// # selected_group=abc  selected_asset=def
    /// id                                   kind      x      y      w      h  metadata
    /// culling.bottom.action.pick           button  320.0  840.0   80.0   32.0
    /// culling.center.large_image           image    12.4   84.0  600.5  400.0  asset_id=ABC
    /// ```
    /// 行内按 id 字典序排列，便于 diff。header 可选附加上下文 kv 对。
    func textualReport(contextMetadata: [String: String] = [:], now: Date = .now) -> String {
        let elements = sortedElements()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = []
        lines.append("# Luma UI Inspector — \(formatter.string(from: now)) (\(elements.count) elements)")
        if !contextMetadata.isEmpty {
            let ctx = contextMetadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "  ")
            lines.append("# \(ctx)")
        }

        // 固定列宽的纯文本表格，等宽字体下对齐、diff 友好。
        let idWidth = max(36, (elements.map { $0.id.count }.max() ?? 0) + 2)
        let kindWidth = max(8, (elements.map { $0.kind.count }.max() ?? 0) + 2)

        lines.append(
            Self.padRight("id", width: idWidth)
            + " " + Self.padRight("kind", width: kindWidth)
            + " " + Self.padLeft("x", width: 8)
            + " " + Self.padLeft("y", width: 8)
            + " " + Self.padLeft("w", width: 8)
            + " " + Self.padLeft("h", width: 8)
            + "  metadata"
        )

        for element in elements {
            let frame = element.frameInWindow
            let metaFragment = element.metadata.isEmpty ? "" :
                element.metadata
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
            lines.append(
                Self.padRight(element.id, width: idWidth)
                + " " + Self.padRight(element.kind, width: kindWidth)
                + " " + Self.padLeft(Self.formatCoordinate(frame.minX), width: 8)
                + " " + Self.padLeft(Self.formatCoordinate(frame.minY), width: 8)
                + " " + Self.padLeft(Self.formatCoordinate(frame.width), width: 8)
                + " " + Self.padLeft(Self.formatCoordinate(frame.height), width: 8)
                + "  " + metaFragment
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func padRight(_ s: String, width: Int) -> String {
        if s.count >= width { return s }
        return s + String(repeating: " ", count: width - s.count)
    }

    private static func padLeft(_ s: String, width: Int) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }

    /// 测试辅助：清空全部注册项。
    func clear() {
        elements.removeAll()
        isInspectorEnabled = false
    }
}

/// SwiftUI 的命名坐标空间标识。整个 UI 树以主窗口为参照，方便所有 `lumaTrack` 节点
/// 用同一个坐标系描述自己的位置（避免每个父容器再起一套局部坐标）。
enum LumaCoordinateSpace {
    static let window = "LumaWindow"
}
