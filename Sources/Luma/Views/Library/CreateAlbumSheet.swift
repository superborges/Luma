import SwiftUI

struct CreateAlbumSheet: View {
    @Bindable var store: LibraryStore
    @Binding var isPresented: Bool
    @State private var albumName = ""
    @State private var selectedExpeditionId: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("相册名称") {
                    TextField("输入相册名称", text: $albumName)
                }

                Section("关联旅程（可选）") {
                    Picker("旅程", selection: $selectedExpeditionId) {
                        Text("不关联").tag(UUID?.none)
                        ForEach(store.expeditions.filter { !$0.isMacPhotos }) { expedition in
                            Text(expedition.name).tag(UUID?.some(expedition.id))
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("新建相册")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { createAlbum() }
                        .disabled(albumName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
    }

    private func createAlbum() {
        let name = albumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try store.createManualAlbum(name: name, expeditionId: selectedExpeditionId)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
