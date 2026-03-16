import SwiftUI

struct AddGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupStore: GroupStore

    @State private var groupName = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("グループ名") {
                    TextField("グループ名を入力", text: $groupName)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("グループを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task { await addGroup() }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
            }
        }
    }

    private func addGroup() async {
        let trimmed = groupName.trimmingCharacters(in: .whitespaces)
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            try await groupStore.createGroup(name: trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddGroupView()
        .environmentObject(GroupStore())
}
