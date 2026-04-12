import SwiftUI

struct CullingHubView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        CullingWorkspaceView(store: store)
    }
}
