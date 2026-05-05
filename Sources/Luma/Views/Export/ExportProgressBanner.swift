import SwiftUI

/// 导出阶段悬浮于底部的轻量进度条。
/// 主要场景：Photos 源 → Folder/LR 时的「下载原图 N/M」、写入阶段、清理阶段。
struct ExportProgressBanner: View {
    let progress: ExportProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.accentColor.opacity(0.8), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                if progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .frame(width: 240)
                        .tint(.accentColor)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                if let name = progress.currentName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .frame(maxWidth: 360)
    }

    private var iconName: String {
        switch progress.phase {
        case .preparing, .confirming: return "hourglass"
        case .fetchingOriginals: return "icloud.and.arrow.down"
        case .writing: return "square.and.arrow.up"
        case .cleaning: return "trash"
        case .archiving: return "archivebox"
        case .finalizing: return "checkmark.seal"
        }
    }

    private var headline: String {
        switch progress.phase {
        case .preparing:
            return "准备导出…"
        case .confirming:
            return "等待你的确认…"
        case .fetchingOriginals:
            if progress.total > 0 {
                return "下载原图 \(progress.completed)/\(progress.total)"
            }
            return "正在向 iCloud 请求原图…"
        case .writing:
            return progress.total > 0 ? "正在写入 \(progress.total) 张…" : "正在写入…"
        case .cleaning:
            return "整理源相册…"
        case .archiving:
            if progress.total > 0 {
                return "归档处理 \(progress.completed)/\(progress.total)"
            }
            return "归档未选照片…"
        case .finalizing:
            return "整理结果…"
        }
    }
}
