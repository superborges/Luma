import SwiftUI

struct EditingHubView: View {
    var body: some View {
        ContentUnavailableView(
            "编辑",
            systemImage: "slider.horizontal.3",
            description: Text("编辑会话与生产工作区即将接入。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
