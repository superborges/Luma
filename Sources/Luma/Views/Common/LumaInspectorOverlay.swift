import AppKit
import SwiftUI

/// Luma UI Inspector 可视化 overlay：在主窗口之上叠一层红色线框，每个红框代表一个通过
/// `.lumaTrack(...)` 注册到 `UIRegistry` 的元素；框左上角贴一个 id 标签。
///
/// 这是 **Luma 长期 debug 基建**的一部分，用来替代「让用户截图」的 UI 对齐方式：
/// 用户按 `Cmd+Shift+U` 打开 overlay，肉眼就能认出框 → id；需要深度 debug 时点
/// 工具条里的 "Copy report" 把 id/frame 表格复制到剪贴板，粘贴给 AI / 队友即可。
///
/// 设计：
/// - 框与 id 标签用一个 `Canvas` 画，成本很低，几百个元素也不会卡；
/// - 底层 `allowsHitTesting(false)`，不拦截任何真实 UI 点击；
/// - 只有右上角浮动工具条是可点的（两个按钮 + 元素计数）；
/// - 依赖 `ContentView` 最外层设置的 `LumaCoordinateSpace.window` 命名坐标空间 —
///   `lumaTrack` 写进 registry 的 frame 正是这个坐标系里的值，所以 Canvas 直接用即可。
struct LumaInspectorOverlay: View {
    let registry: UIRegistry
    var contextMetadataProvider: () -> [String: String] = { [:] }
    var onClose: () -> Void

    var body: some View {
        // 显式读一次 elements，让 SwiftUI 追踪到 @Observable 订阅 —— 这样无论是新元素
        // 注册、旧元素 unregister 还是 frame 变了，overlay 都会 re-evaluate 并重画。
        let elements = registry.sortedElements()

        ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                for element in elements {
                    Self.drawElement(element: element, ctx: ctx, size: size)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            toolbar(count: elements.count)
                .padding(12)
        }
        .accessibilityIdentifier("debug.inspector.overlay")
    }

    // MARK: Canvas 绘制

    /// 画单个 element 的框 + id 标签。`static` 以便 SwiftUI 不把整个 View 值捕获进闭包。
    private static func drawElement(element: UIElementInfo, ctx: GraphicsContext, size: CGSize) {
        let frame = element.frameInWindow
        // 过滤无效/越界的 frame：GeometryReader 初始化瞬间可能上报 .zero。
        guard frame.width > 1, frame.height > 1 else { return }
        guard frame.maxX > 0, frame.maxY > 0 else { return }
        guard frame.minX < size.width, frame.minY < size.height else { return }

        let framePath = Path(frame)
        ctx.stroke(framePath, with: .color(.red.opacity(0.85)), lineWidth: 1.2)

        // id 标签 —— 显示最后 2 段，避免每个标签都顶着前缀 "culling." 看着冗余。
        let displayID = shortDisplayID(for: element.id)
        let text = Text(displayID)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white)
        var resolved = ctx.resolve(text)
        resolved.shading = .color(.white)

        // measure 里给足宽度，让文字不要被截断。
        let textSize = resolved.measure(in: CGSize(width: 600, height: 20))
        let hPad: CGFloat = 3
        let vPad: CGFloat = 1
        let labelSize = CGSize(width: textSize.width + hPad * 2, height: textSize.height + vPad * 2)

        // 默认把标签贴在矩形外顶上；顶太挤就改贴在矩形内左上。
        var labelOrigin = CGPoint(x: frame.minX, y: frame.minY - labelSize.height)
        if labelOrigin.y < 0 {
            labelOrigin.y = frame.minY + 1
        }
        // 避免伸出右边：
        if labelOrigin.x + labelSize.width > size.width {
            labelOrigin.x = size.width - labelSize.width
        }

        let labelRect = CGRect(origin: labelOrigin, size: labelSize)
        ctx.fill(Path(labelRect), with: .color(.black.opacity(0.80)))
        ctx.stroke(Path(labelRect), with: .color(.red.opacity(0.9)), lineWidth: 0.8)
        ctx.draw(
            resolved,
            at: CGPoint(x: labelOrigin.x + hPad, y: labelOrigin.y + vPad),
            anchor: .topLeading
        )
    }

    /// `"culling.right.cell[abc]" -> "right.cell[abc]"`：只保留最后两段。
    private static func shortDisplayID(for id: String) -> String {
        let segments = id.split(separator: ".")
        if segments.count >= 2 {
            return segments.suffix(2).joined(separator: ".")
        }
        return id
    }

    // MARK: 工具条

    private func toolbar(count: Int) -> some View {
        HStack(spacing: 10) {
            Text("UI Inspector · \(count)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .accessibilityIdentifier("debug.inspector.toolbar.count")

            Button {
                copyReport()
            } label: {
                Text("Copy report")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("debug.inspector.toolbar.copy")

            Button {
                RuntimeTrace.event(
                    "ui_inspector_closed",
                    category: "ui",
                    metadata: ["source": "toolbar_close_button"]
                )
                onClose()
            } label: {
                Text("✕")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("debug.inspector.toolbar.close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.red.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
    }

    private func copyReport() {
        let report = registry.textualReport(contextMetadata: contextMetadataProvider())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)

        RuntimeTrace.event(
            "ui_inspector_report_copied",
            category: "ui",
            metadata: [
                "element_count": String(registry.elements.count),
                "byte_length": String(report.utf8.count)
            ]
        )
    }
}
