import SwiftUI

/// Bolder Material-style `more_vert` (three vertical dots).
struct ExpeditionMoreVertIndicator: View {
    /// Align with Stitch `text-outline-variant` / subdued `more_vert` (not high-contrast).
    private let dotColor = StitchTheme.outlineVariant.opacity(0.85)

    /// Heavier than default glyph weight to match Stitch `more_vert`.
    private let dotDiameter: CGFloat = 6
    private let dotSpacing: CGFloat = 3

    var body: some View {
        VStack(spacing: dotSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotDiameter, height: dotDiameter)
            }
        }
        .frame(width: 20, height: 28, alignment: .center)
        .accessibilityLabel("More options")
    }
}
