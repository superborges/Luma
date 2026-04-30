import SwiftUI

/// 新建导入来源菜单内容，供首页与选片顶栏复用。
struct ImportSourceMenuItems: View {
    @Bindable var store: ProjectStore

    var body: some View {
        Button {
            // Menu 收合时若直接 `Task { await }`，子任务有概率被随菜单一起取消，表现为「点了没反应」。
            // 先 `DispatchQueue.main.async` 脱离菜单的同步更新周期，再 @MainActor 跑导入。
            scheduleImport { await $0.importFolder() }
        } label: {
            Label("普通目录", systemImage: "folder")
        }
        // SD 卡：未检测到挂载时，直接禁用并改文案，省得用户白点。
        Button {
            scheduleImport { await $0.importSDCard() }
        } label: {
            if store.hasConnectedSDCard {
                let detail = store.connectedSDCardNames.first.map { "（\($0)）" } ?? ""
                Label("SD 卡\(detail)", systemImage: "sdcard.fill")
            } else {
                Label("SD 卡（未检测到）", systemImage: "sdcard")
            }
        }
        .disabled(!store.hasConnectedSDCard)
        Button {
            scheduleImportAfterMenuTeardown { await $0.presentPhotosImportPicker() }
        } label: {
            Label("Mac · 照片", systemImage: "photo.on.rectangle.angled")
        }
        // iPhone USB：未连接 / 未解锁时禁用，提示文案改成"插入并解锁 iPhone"。
        Button {
            scheduleImport { await $0.importIPhone() }
        } label: {
            if store.hasConnectedIPhone {
                let detail = store.connectedIPhoneNames.first.map { "（\($0)）" } ?? ""
                Label("iPhone · USB 直连\(detail)", systemImage: "iphone.gen3")
            } else {
                Label("iPhone · USB 直连（请插入并解锁）", systemImage: "iphone.slash")
            }
        }
        .disabled(!store.hasConnectedIPhone)
        if store.recoverableImportSession != nil {
            Divider()
            Button {
                scheduleImport { await $0.resumeRecoverableImport() }
            } label: {
                Label("继续未完成的导入", systemImage: "arrow.clockwise.circle")
            }
            .disabled(store.isImporting)
        }
    }

    private func scheduleImport(_ work: @escaping @MainActor (ProjectStore) async -> Void) {
        let target = store
        DispatchQueue.main.async {
            Task { @MainActor in
                await work(target)
            }
        }
    }

    /// 专供「从照片导入」：在单次 `main.async` 之外再多排一程，等 SwiftUI 菜单/焦点完全落地后再跑异步导入。
    private func scheduleImportAfterMenuTeardown(_ work: @escaping @MainActor (ProjectStore) async -> Void) {
        let target = store
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                Task { @MainActor in
                    await work(target)
                }
            }
        }
    }
}
