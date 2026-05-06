import SwiftUI

struct ActionProgressView: View {
    let progress: ArchiveProgress?
    let jobKind: ActionKind?

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            if let p = progress {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kindLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.85))
                    HStack(spacing: 6) {
                        Text("\(p.completed)/\(p.total)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))
                        if !p.currentName.isEmpty {
                            Text(p.currentName)
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.5))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                if p.total > 0 {
                    ProgressView(value: Double(p.completed), total: Double(p.total))
                        .progressViewStyle(.linear)
                        .frame(width: 100)
                        .tint(.blue)
                }
            } else {
                Text(kindLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.85))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var kindLabel: String {
        switch jobKind {
        case .archiveVideo: return "归档视频中…"
        case .archiveLowres: return "低清保留中…"
        case .archiveMarkerOnly: return "标记归档中…"
        case .exportToFolder: return "导出到文件夹中…"
        case .syncAlbumToPhotos: return "同步到 Photos…"
        case nil: return "处理中…"
        }
    }
}
