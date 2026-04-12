import SwiftUI

struct CullingWorkspaceView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView(store: store)
            HSplitView {
                GroupSidebar(store: store)
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280, maxHeight: .infinity)

                PhotoGrid(store: store)
                    .frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

                DetailPanel(store: store)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
