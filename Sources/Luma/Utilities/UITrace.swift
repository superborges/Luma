import Foundation

/// UI 专属的 trace helper，构建在 `RuntimeTrace` 上。
///
/// 设计原则：
/// - **不污染 trace**：`appear` / `disappear` 默认不发事件（registry 默默更新即可），只有显式 tap / select /
///   `snapshot()` 才写文件。这样在右栏滚动时不会被 100 个 cell 的 lifecycle 淹没。
/// - **trace 自带坐标**：每个 `tap("foo")` 自动从 `UIRegistry` 拉 frame，附在 metadata 里。
///   日后看 trace 就能直接复盘"用户点了屏幕的哪个矩形"，不必再去翻 view code 找位置。
/// - **统一 category**：所有 UI 事件 category=`"ui"`，方便 `rg ',"category":"ui"'` 过滤。
@MainActor
enum UITrace {
    /// 用户对元素的单击。
    static func tap(_ id: String, metadata: [String: String] = [:]) {
        emit(name: "ui_tap", id: id, base: metadata)
    }

    /// 用户对元素的双击。
    static func doubleTap(_ id: String, metadata: [String: String] = [:]) {
        emit(name: "ui_double_tap", id: id, base: metadata)
    }

    /// 选中状态变化（高亮 / 焦点 / 数据驱动的选中）。`value` 适合放被选项的可读描述。
    static func select(_ id: String, value: String? = nil, metadata: [String: String] = [:]) {
        var combined = metadata
        if let value { combined["value"] = value }
        emit(name: "ui_select", id: id, base: combined)
    }

    /// 任意自定义 UI 事件（菜单项、键盘、菜单等）。
    static func event(_ name: String, id: String, metadata: [String: String] = [:]) {
        emit(name: name, id: id, base: metadata)
    }

    /// 把 `UIRegistry` 当前所有元素整批写入 trace。`Cmd+Shift+D` / 性能面板的 "Dump UI 树" 按钮
    /// 触发。一次产生 1 + N 行 jsonl：先写一条 `ui_snapshot_started` 概要，再每个元素一条 `ui_element_state`。
    static func snapshot(reason: String = "manual") {
        let elements = UIRegistry.shared.sortedElements()
        RuntimeTrace.event(
            "ui_snapshot_started",
            category: "ui",
            metadata: [
                "reason": reason,
                "element_count": String(elements.count)
            ]
        )

        for element in elements {
            var meta: [String: String] = [
                "element_id": element.id,
                "kind": element.kind,
                "frame_x": Self.formatCoordinate(element.frameInWindow.minX),
                "frame_y": Self.formatCoordinate(element.frameInWindow.minY),
                "frame_w": Self.formatCoordinate(element.frameInWindow.width),
                "frame_h": Self.formatCoordinate(element.frameInWindow.height)
            ]
            for (key, value) in element.metadata {
                meta["meta_\(key)"] = value
            }
            RuntimeTrace.event("ui_element_state", category: "ui", metadata: meta)
        }
    }

    /// 拼装 trace 用的标准 metadata：始终包含 `element_id`，若该 id 已在 `UIRegistry`
    /// 注册则附上 `kind` 和 `frame_x/y/w/h`。也对外暴露给自定义 trace 调用方使用。
    static func standardMetadata(
        for id: String,
        base: [String: String] = [:],
        registry: UIRegistry = .shared
    ) -> [String: String] {
        var meta = base
        meta["element_id"] = id
        if let info = registry.info(for: id) {
            meta["kind"] = info.kind
            meta["frame_x"] = Self.formatCoordinate(info.frameInWindow.minX)
            meta["frame_y"] = Self.formatCoordinate(info.frameInWindow.minY)
            meta["frame_w"] = Self.formatCoordinate(info.frameInWindow.width)
            meta["frame_h"] = Self.formatCoordinate(info.frameInWindow.height)
        }
        return meta
    }

    private static func emit(name: String, id: String, base: [String: String]) {
        let meta = standardMetadata(for: id, base: base)
        RuntimeTrace.event(name, category: "ui", metadata: meta)
    }

    private static func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
