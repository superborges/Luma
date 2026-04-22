import SwiftUI

/// 导出完成后的结构化摘要：成功/失败/清理统计 + 失败明细 + 后续动作。
/// 替代原本的 alert，对应 PRD「导出页 Step 5」。
struct ExportSummaryView: View {
    @Bindable var store: ProjectStore
    let result: ExportResult

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metricsRow
                    if let albumDescription = result.albumDescription {
                        infoLine(label: "写入相册", value: albumDescription, icon: "rectangle.stack")
                    }
                    if let url = result.destinationURL {
                        infoLine(label: "目标目录", value: url.path, icon: "folder")
                    } else {
                        infoLine(label: "目标", value: result.destinationDescription, icon: "square.and.arrow.up")
                    }
                    if result.cleanedCount > 0 || result.cleanupCancelledCount > 0 {
                        cleanupSection
                    }
                    if !result.failures.isEmpty {
                        failuresSection
                    }
                }
                .padding(20)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: result.failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(result.failures.isEmpty ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.failures.isEmpty ? "导出完成" : "导出完成（含失败项）")
                    .font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var headerSubtitle: String {
        let parts: [String] = [
            "成功 \(result.exportedCount)",
            result.failures.isEmpty ? nil : "失败 \(result.failures.count)",
            result.cleanedCount > 0 ? "清理 \(result.cleanedCount)" : nil,
            result.cleanupCancelledCount > 0 ? "取消清理 \(result.cleanupCancelledCount)" : nil
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(title: "已导出", value: "\(result.exportedCount)", tint: .green, systemImage: "checkmark.circle.fill")
            metricCard(title: "失败", value: "\(result.failures.count)", tint: result.failures.isEmpty ? .secondary : .orange, systemImage: "xmark.octagon")
            if result.cleanedCount > 0 {
                metricCard(title: "已清理", value: "\(result.cleanedCount)", tint: .red.opacity(0.85), systemImage: "trash")
            }
            if result.cleanupCancelledCount > 0 {
                metricCard(title: "取消清理", value: "\(result.cleanupCancelledCount)", tint: .gray, systemImage: "hand.raised")
            }
            if result.skippedCount > 0 {
                metricCard(title: "跳过", value: "\(result.skippedCount)", tint: .gray, systemImage: "forward.end")
            }
        }
    }

    private func metricCard(title: String, value: String, tint: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infoLine(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("源相册清理")
                .font(.subheadline.weight(.semibold))
            if result.cleanedCount > 0 {
                Text("已从「照片 App」原始相册移除 \(result.cleanedCount) 张未选原图（30 天内可在系统「最近删除」中恢复）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if result.cleanupCancelledCount > 0 {
                Text("有 \(result.cleanupCancelledCount) 张原图因你在系统对话框点击取消，未被删除。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var failuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("失败明细")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(result.failures.count) 项")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(result.failures.prefix(20)) { failure in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.fileName)
                                .font(.callout.weight(.medium))
                            Text(failure.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.4)
                }
                if result.failures.count > 20 {
                    Text("还有 \(result.failures.count - 20) 项未展开。完整列表已写入 trace 与 manifest。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if !result.failures.isEmpty {
                Button {
                    store.retryFailedExports()
                } label: {
                    Label("仅重试失败项", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command])
            }
            if result.destinationURL != nil {
                Button {
                    store.revealLastExportDestination()
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            if result.destinationDescription.localizedCaseInsensitiveContains("照片 App") || result.albumDescription != nil {
                Button {
                    store.openPhotosApp()
                } label: {
                    Label("打开 Photos", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button {
                store.dismissExportResult()
                store.leaveProjectToSessionList()
            } label: {
                Text("返回首页")
            }
            .buttonStyle(.bordered)
            Button {
                store.dismissExportResult()
            } label: {
                Text("完成")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
