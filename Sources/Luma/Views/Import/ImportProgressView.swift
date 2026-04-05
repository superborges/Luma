import SwiftUI

struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ProgressView(value: progress.fractionCompleted)
            HStack {
                Text("\(progress.completed) / \(max(progress.total, 1))")
                    .foregroundStyle(.secondary)
                Spacer()
                if let currentItemName = progress.currentItemName {
                    Text(currentItemName)
                        .lineLimit(2)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        switch progress.phase {
        case .scanning:
            return "扫描素材中"
        case .preparingThumbnails:
            return "生成缩略图"
        case .copyingPreviews:
            return "拷贝预览图"
        case .copyingOriginals:
            return "拷贝原始素材"
        case .paused:
            return "导入已暂停"
        case .finalizing:
            return "完成项目整理"
        }
    }
}
