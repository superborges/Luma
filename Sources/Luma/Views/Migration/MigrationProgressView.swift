import SwiftUI

struct MigrationProgressView: View {
    let progress: MigrationProgress?
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(StitchTheme.primary)

            VStack(spacing: 8) {
                Text("数据迁移")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                Text("检测到旧版数据，正在迁移到新格式…")
                    .font(.system(size: 14))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
            }

            if let error {
                errorSection(error)
            } else if let progress {
                progressSection(progress)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .padding(48)
        .frame(width: 480)
        .background(StitchTheme.surfaceContainer)
        .cornerRadius(16)
    }

    private func progressSection(_ p: MigrationProgress) -> some View {
        VStack(spacing: 16) {
            if p.phase == .completed {
                completedSection(p)
            } else {
                activeSection(p)
            }
        }
    }

    private func activeSection(_ p: MigrationProgress) -> some View {
        VStack(spacing: 12) {
            if !p.currentSessionName.isEmpty {
                Text("正在迁移：\(p.currentSessionName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StitchTheme.onSurface)
                    .lineLimit(1)
            }

            VStack(spacing: 4) {
                let sessionFraction = p.totalSessions > 0
                    ? Double(p.currentSession) / Double(p.totalSessions)
                    : 0
                ProgressView(value: sessionFraction)
                    .progressViewStyle(.linear)
                    .tint(StitchTheme.primary)

                HStack {
                    Text(phaseLabel(p.phase))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(p.currentSession) / \(p.totalSessions) 旅程")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if p.totalAssets > 0 {
                VStack(spacing: 4) {
                    let assetFraction = Double(p.currentAsset) / Double(p.totalAssets)
                    ProgressView(value: assetFraction)
                        .progressViewStyle(.linear)
                        .tint(StitchTheme.primary.opacity(0.6))

                    HStack {
                        Text("照片")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(p.currentAsset) / \(p.totalAssets)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func completedSection(_ p: MigrationProgress) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("迁移完成")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(StitchTheme.onSurface)
            Text("已迁移 \(p.totalSessions) 个旅程")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("迁移失败")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(StitchTheme.onSurface)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button("重试") { onRetry() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func phaseLabel(_ phase: MigrationPhase) -> String {
        switch phase {
        case .backup: return "备份旧数据…"
        case .migratingSession: return "迁移中…"
        case .writingMarker: return "完成中…"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}
