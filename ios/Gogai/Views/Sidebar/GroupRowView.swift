import SwiftUI

struct GroupRowView: View {
    let group: Group
    @Binding var selectedGroupId: Int?

    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore

    @State private var showEditAlert = false
    @State private var editName = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        Button {
            selectedGroupId = group.id
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .contextMenu {
            Button {
                editName = group.name
                showEditAlert = true
            } label: {
                Label("名前を変更", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .alert("グループ名を変更", isPresented: $showEditAlert) {
            TextField("グループ名", text: $editName)
            Button("変更") {
                Task {
                    try? await groupStore.updateGroup(id: group.id, name: editName)
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("グループを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                Task {
                    try? await groupStore.deleteGroup(id: group.id)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このグループのフィードはグループなしになります")
        }
    }
}
