import SwiftUI

struct AddGroupView: View {
    @EnvironmentObject private var groupStore: GroupStore

    @State private var groupName = ""

    var body: some View {
        FormSheet(
            title: "グループを追加",
            confirmLabel: "追加",
            confirmDisabled: groupName.trimmingCharacters(in: .whitespaces).isEmpty,
            onSubmit: {
                let trimmed = groupName.trimmingCharacters(in: .whitespaces)
                try await groupStore.createGroup(name: trimmed)
            }
        ) {
            Section("グループ名") {
                TextField("グループ名を入力", text: $groupName)
            }
        }
    }
}

#Preview {
    AddGroupView()
        .environmentObject(GroupStore())
}
