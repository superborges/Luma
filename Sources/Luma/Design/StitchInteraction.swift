import SwiftUI

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

// MARK: - CTA hover (`hover:opacity-90`)

private struct StitchHoverDimmingModifier: ViewModifier {
    var dimmedOpacity: CGFloat
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .opacity(hovered ? dimmedOpacity : 1)
            .animation(.easeInOut(duration: 0.2), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    /// Primary gradient buttons: slight dim on hover (Stitch `hover:opacity-90`).
    func stitchHoverDimming(opacity whenHovered: CGFloat = 0.92) -> some View {
        modifier(StitchHoverDimmingModifier(dimmedOpacity: whenHovered))
    }
}

// MARK: - Recent bento image (`group-hover:scale-*` + duration)

private struct StitchImageHoverScaleModifier: ViewModifier {
    var hoverScale: CGFloat
    var duration: Double
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? hoverScale : 1)
            .animation(.easeInOut(duration: duration), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    /// Featured card: ~1.05 / 0.7s; secondary: ~1.10 / 0.5s in Stitch HTML.
    func stitchImageHoverScale(_ scale: CGFloat, duration: Double) -> some View {
        modifier(StitchImageHoverScaleModifier(hoverScale: scale, duration: duration))
    }
}

// MARK: - List row (`hover:bg-surface-container-high` + `transition-colors`)

private struct StitchListRowHoverModifier: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(
                Rectangle()
                    .fill(hovered ? StitchTheme.surfaceContainerHigh.opacity(0.55) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: hovered)
            )
            .onHover { hovered = $0 }
    }
}

extension View {
    func stitchListRowHoverBackground() -> some View {
        modifier(StitchListRowHoverModifier())
    }
}

// MARK: - Subtle card hover (grid tiles)

private struct StitchSubtleCardHoverModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(StitchTheme.surfaceContainerHigh.opacity(hovered ? 0.18 : 0))
                    .animation(.easeInOut(duration: 0.15), value: hovered)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

extension View {
    func stitchSubtleCardHover(cornerRadius: CGFloat = 8) -> some View {
        modifier(StitchSubtleCardHoverModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Top bar icon circles (`hover:bg-neutral-800/50`)

struct StitchToolbarIconCircleButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(StitchTheme.sidebarInactiveText)
                .padding(8)
                .background(
                    Circle()
                        .fill(hovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }
}

// MARK: - Culling / system-material list rows (adaptive primary wash)

private struct StitchAdaptiveListRowHoverModifier: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(
                Rectangle()
                    .fill(Color.primary.opacity(hovered ? 0.055 : 0))
                    .animation(.easeInOut(duration: 0.15), value: hovered)
            )
            .onHover { hovered = $0 }
    }
}

extension View {
    /// For `ultraThinMaterial` / `windowBackgroundColor` hubs: neutral hover wash.
    func stitchAdaptiveListRowHover() -> some View {
        modifier(StitchAdaptiveListRowHoverModifier())
    }
}

// MARK: - Group sidebar (hover only when not selected)

private struct StitchUnselectedHoverWashModifier: ViewModifier {
    var isSelected: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .fill(!isSelected && hovered ? Color.primary.opacity(0.06) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: hovered)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

extension View {
    /// Culling `GroupSidebar` rows: subtle hover without clashing with selection fill.
    func stitchUnselectedHoverWash(isSelected: Bool) -> some View {
        modifier(StitchUnselectedHoverWashModifier(isSelected: isSelected))
    }
}

// MARK: - Asset grid tiles (preview image only)

private struct StitchAssetPreviewHoverScaleModifier: ViewModifier {
    var scale: CGFloat
    var duration: Double
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? scale : 1)
            .animation(.easeInOut(duration: duration), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    /// Thumbnail / burst cover: short, subtle zoom (P2).
    func stitchAssetPreviewHoverScale(_ scale: CGFloat = 1.035, duration: Double = 0.22) -> some View {
        modifier(StitchAssetPreviewHoverScaleModifier(scale: scale, duration: duration))
    }
}
