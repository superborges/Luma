import SwiftUI

/// v1 首页占位：Import Session 列表 + "新建 Import Session" 入口。
/// Phase 1 会接入真正的 SessionStore；当前只渲染占位让 ContentView 可编译运行。
struct SessionListView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StitchTheme.background)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurface)
                Text("从 SD 卡 / 本地目录 / Mac·照片 App / iPhone 创建一个 Import Session")
                    .font(.system(size: 12))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    Task { await store.importFolder() }
                } label: {
                    Label("普通目录", systemImage: "folder")
                }
                Button {
                    Task { await store.importSDCard() }
                } label: {
                    Label("SD 卡", systemImage: "sdcard")
                }
                Button {
                    Task { await store.importPhotosLibrary() }
                } label: {
                    Label("Mac · 照片 App (iCloud)", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    Task { await store.importIPhone() }
                } label: {
                    Label("iPhone · USB 直连", systemImage: "iphone")
                }
            } label: {
                Label("新建 Import Session", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(StitchTheme.primary)
                    )
                    .foregroundStyle(StitchTheme.onPrimary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var content: some View {
        if store.projectSummaries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.projectSummaries) { summary in
                        SessionRow(summary: summary) {
                            store.openProject(summary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(StitchTheme.onSurfaceVariant.opacity(0.6))
            Text("还没有 Import Session")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(StitchTheme.onSurface)
            Text("点击右上角「新建 Import Session」开始")
                .font(.system(size: 12))
                .foregroundStyle(StitchTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let summary: ProjectSummary
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(StitchTheme.surfaceContainerHigh)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 18))
                            .foregroundStyle(StitchTheme.onSurfaceVariant)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StitchTheme.onSurface)
                    Text(stateText)
                        .font(.system(size: 11))
                        .foregroundStyle(StitchTheme.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurfaceVariant.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovered ? StitchTheme.surfaceContainerHigh : StitchTheme.surfaceContainer)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }

    private var stateText: String {
        switch summary.state {
        case .ready(let assetCount, let groupCount):
            return "\(assetCount) 张 · \(groupCount) 组"
        case .unavailable(let reason):
            return "无法读取：\(reason)"
        }
    }
}
