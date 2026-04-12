import SwiftUI

extension AppSection {
    /// English labels matching Stitch HTML `9bd72cc1`.
    fileprivate var stitchNavTitle: String {
        switch self {
        case .library: return "Library"
        case .imports: return "Imports"
        case .culling: return "Culling"
        case .editing: return "Editing"
        case .export: return "Export"
        }
    }

    fileprivate var stitchNavIcon: String {
        switch self {
        case .library: return "photo.on.rectangle.angled"
        case .imports: return "square.and.arrow.down"
        case .culling: return "checkmark.circle"
        case .editing: return "slider.horizontal.3"
        case .export: return "square.and.arrow.up"
        }
    }
}

struct SideNavBar: View {
    @Environment(\.openSettings) private var openSettings
    @Binding var currentSection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            nav
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(width: 256, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(StitchTheme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [StitchTheme.primary, StitchTheme.primaryContainer],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StitchTheme.onPrimary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Luma")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.96))
                    .tracking(-0.5)
                Text("Obsidian Pro")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StitchTheme.sidebarActiveText)
                    .textCase(.uppercase)
                    .tracking(2.4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .padding(.bottom, 16)
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AppSection.allCases) { section in
                navRow(section)
            }
        }
    }

    private func navRow(_ section: AppSection) -> some View {
        SideNavItemRow(
            section: section,
            isSelected: currentSection == section,
            select: { currentSection = section }
        )
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.top, 16)
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [StitchTheme.surfaceContainerHigh, StitchTheme.surfaceContainerHighest],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(StitchTheme.onSurface.opacity(0.7))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alex Sterling")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.96))
                        .lineLimit(1)
                    Text("Vault: 98% Healthy")
                        .font(.system(size: 10))
                        .foregroundStyle(StitchTheme.sidebarInactiveText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SideNavFooterSettingsButton(action: { openSettings() })
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}

private struct SideNavItemRow: View {
    let section: AppSection
    let isSelected: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: section.stitchNavIcon)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 22, alignment: .center)
                Text(section.stitchNavTitle)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .tracking(-0.2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? StitchTheme.sidebarActiveText : StitchTheme.sidebarInactiveText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { hovered = $0 }
    }

    private var rowFill: Color {
        if isSelected { return StitchTheme.sidebarActiveBackground }
        if hovered { return Color.white.opacity(0.08) }
        return .clear
    }
}

private struct SideNavFooterSettingsButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(StitchTheme.sidebarInactiveText)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hovered ? Color.white.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }
}
