import SwiftUI

// MARK: - Hover 交互全局禁用说明
//
// 2026-04-22：因 Swift 6.2 / SwiftUI 7.3 / macOS 26 / arm64e 在
// `swift_task_isCurrentExecutorWithFlagsImpl` 路径上的 PAC failure，
// 凡是 SwiftUI `.onHover` 或 NSView @objc method 入口都会触发段错误
// （详见 KNOWN_ISSUES.md Round 6/7）。
//
// 临时方案：保留以下所有 modifier / View 的函数签名以兼容调用方，
// 但移除内部 hover 状态和 `.onHover` / `.lumaSafeHover` 调用。
// hover 高亮属于"有更好、没有也行"的视觉糖，等 SDK 修了再恢复。

// MARK: - Global press (Stitch `active:scale-[0.98]` / `scale-95`)

/// Apply at app shell (e.g. `ContentView`) so plain buttons share one tactile scale.
struct StitchPressScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98
    var pressedOpacity: CGFloat = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - CTA hover (`hover:opacity-90`) — DISABLED

private struct StitchHoverDimmingModifier: ViewModifier {
    var dimmedOpacity: CGFloat
    func body(content: Content) -> some View { content }
}

extension View {
    /// Primary gradient buttons: slight dim on hover (Stitch `hover:opacity-90`).
    /// **Hover 已禁用**（见文件顶部说明）；保留 API 以兼容调用方。
    func stitchHoverDimming(opacity whenHovered: CGFloat = 0.92) -> some View {
        modifier(StitchHoverDimmingModifier(dimmedOpacity: whenHovered))
    }
}

// MARK: - Recent bento image (`group-hover:scale-*` + duration) — DISABLED

private struct StitchImageHoverScaleModifier: ViewModifier {
    var hoverScale: CGFloat
    var duration: Double
    func body(content: Content) -> some View { content }
}

extension View {
    func stitchImageHoverScale(_ scale: CGFloat, duration: Double) -> some View {
        modifier(StitchImageHoverScaleModifier(hoverScale: scale, duration: duration))
    }
}

// MARK: - List row hover background — DISABLED

private struct StitchListRowHoverModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    func stitchListRowHoverBackground() -> some View {
        modifier(StitchListRowHoverModifier())
    }
}

// MARK: - Subtle card hover (grid tiles) — DISABLED

private struct StitchSubtleCardHoverModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    func body(content: Content) -> some View { content }
}

extension View {
    func stitchSubtleCardHover(cornerRadius: CGFloat = 8) -> some View {
        modifier(StitchSubtleCardHoverModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Top bar icon circles — hover state removed

struct StitchToolbarIconCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(StitchTheme.sidebarInactiveText)
                .padding(8)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Adaptive list row hover — DISABLED

private struct StitchAdaptiveListRowHoverModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    /// For `ultraThinMaterial` / `windowBackgroundColor` hubs: neutral hover wash.
    func stitchAdaptiveListRowHover() -> some View {
        modifier(StitchAdaptiveListRowHoverModifier())
    }
}

// MARK: - Group sidebar unselected hover wash — DISABLED

private struct StitchUnselectedHoverWashModifier: ViewModifier {
    var isSelected: Bool
    func body(content: Content) -> some View { content }
}

extension View {
    /// Culling `GroupSidebar` rows: subtle hover without clashing with selection fill.
    func stitchUnselectedHoverWash(isSelected: Bool) -> some View {
        modifier(StitchUnselectedHoverWashModifier(isSelected: isSelected))
    }
}

// MARK: - Asset grid tile preview hover scale — DISABLED

private struct StitchAssetPreviewHoverScaleModifier: ViewModifier {
    var scale: CGFloat
    var duration: Double
    func body(content: Content) -> some View { content }
}

extension View {
    /// Thumbnail / burst cover: short, subtle zoom (P2).
    func stitchAssetPreviewHoverScale(_ scale: CGFloat = 1.035, duration: Double = 0.22) -> some View {
        modifier(StitchAssetPreviewHoverScaleModifier(scale: scale, duration: duration))
    }
}
