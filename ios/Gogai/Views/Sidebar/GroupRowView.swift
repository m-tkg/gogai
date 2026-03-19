import SwiftUI

struct GroupRowView: View {
    let group: Group
    @Binding var selectedGroupId: Int?
    var onNavigate: ((ArticleDestination) -> Void)?

    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore

    @State private var showEditAlert = false
    @State private var editName = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack {
            // フォルダアイコン + chevron: タップで展開・折りたたみ
            Button {
                groupStore.toggleExpanded(id: group.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: group.isSecret ? "folder.badge.minus" : "folder")
                        .foregroundStyle(group.isSecret ? .orange : .secondary)
                    Image(systemName: groupStore.isExpanded(id: group.id) ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                }
            }

            // グループ名: タップでグループ記事一覧へ
            Button {
                selectedGroupId = group.id
                onNavigate?(ArticleDestination(feedId: nil, groupId: group.id))
            } label: {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            if groupStore.showSecretGroups {
                Button {
                    Task {
                        try? await groupStore.updateGroup(id: group.id, name: group.name, isSecret: group.isSecret ? 0 : 1)
                    }
                } label: {
                    Image(systemName: group.isSecret ? "lock.fill" : "lock.open")
                        .foregroundStyle(group.isSecret ? .orange : .secondary)
                        .font(.caption)
                }
                Button {
                    editName = group.name
                    showEditAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .contextMenu {
            Button {
                editName = group.name
                showEditAlert = true
            } label: {
                Label("名前を変更", systemImage: "pencil")
            }
            Button {
                Task {
                    try? await groupStore.updateGroup(id: group.id, name: group.name, isSecret: group.isSecret ? 0 : 1)
                }
            } label: {
                Label(
                    group.isSecret ? "シークレットを解除" : "シークレットに設定",
                    systemImage: group.isSecret ? "lock.open" : "lock"
                )
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
