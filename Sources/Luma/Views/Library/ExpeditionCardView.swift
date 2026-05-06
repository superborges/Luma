import SwiftUI

struct ExpeditionCardView: View {
    let expedition: Expedition
    let assetCount: Int
    let groupCount: Int
    let invalidRefCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                coverImage
                    .frame(height: 160)
                    .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(expedition.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(StitchTheme.onSurface)
                        Spacer()
                        if invalidRefCount > 0 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                        }
                        statusBadge
                    }

                    HStack(spacing: 12) {
                        Label("\(assetCount)", systemImage: "photo")
                        if groupCount > 0 {
                            Label("\(groupCount)", systemImage: "rectangle.3.group")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)

                    if let subtitle = expedition.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .background(StitchTheme.surfaceContainer)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(StitchTheme.outlineVariant, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var coverImage: some View {
        ZStack {
            StitchTheme.surfaceContainerLow
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(Color(white: 0.25))
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch expedition.status {
            case .importing: return ("导入中", .orange)
            case .analyzing: return ("分析中", .purple)
            case .reviewing: return ("选片中", .blue)
            case .completed: return ("已完成", .green)
            case .archived: return ("已归档", .gray)
            }
        }()
        return Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}
