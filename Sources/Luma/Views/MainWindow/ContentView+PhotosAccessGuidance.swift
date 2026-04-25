import SwiftUI

extension View {
    /// 主窗口内、与暗色主界面一致的照片库权限/排队提示；避免用 NSAlert 显得陈旧。
    func lumaPhotosAccessGuidanceAlert(store: ProjectStore) -> some View {
        alert(
            store.photosAccessGuidance?.title ?? "照片图库",
            isPresented: Binding(
                get: { store.photosAccessGuidance != nil },
                set: { if !$0 { store.dismissPhotosAccessGuidance() } }
            ),
            presenting: store.photosAccessGuidance
        ) { guide in
            if guide.shouldOfferSystemSettings {
                Button("打开系统设置") {
                    SystemPrivacyURL.openPhotoLibraryPrivacySettings()
                    store.dismissPhotosAccessGuidance()
                }
            }
            Button("好", role: .cancel) {
                store.dismissPhotosAccessGuidance()
            }
        } message: { guide in
            Text(guide.message)
        }
    }
}
