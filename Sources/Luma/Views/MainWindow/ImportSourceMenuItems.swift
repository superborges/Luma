import SwiftUI

/// 新建导入来源菜单内容，供首页与选片顶栏复用。
struct ImportSourceMenuItems: View {
    @Bindable var store: ProjectStore

    var body: some View {
        Button {
            Task { await store.importFolder() }
        } label: {
            Label("普通目录", systemImage: "folder")
        }
        // SD 卡：未检测到挂载时，直接禁用并改文案，省得用户白点。
        Button {
            Task { await store.importSDCard() }
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
            // 必须 async 启动：先把 PhotoKit 授权对话框走完再弹 picker，避免 sheet 叠 sheet
            // 跟 PhotoKit 守护进程初始化时序冲突。详见 ProjectStore.presentPhotosImportPicker。
            Task { await store.presentPhotosImportPicker() }
        } label: {
            Label("Mac · 照片 App (iCloud)", systemImage: "photo.on.rectangle.angled")
        }
        // iPhone USB：未连接 / 未解锁时禁用，提示文案改成"插入并解锁 iPhone"。
        Button {
            Task { await store.importIPhone() }
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
                Task { await store.resumeRecoverableImport() }
            } label: {
                Label("继续未完成的导入", systemImage: "arrow.clockwise.circle")
            }
            .disabled(store.isImporting)
        }
    }
}
