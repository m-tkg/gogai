import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var groupStore: GroupStore

    @State private var urlText = ""
    @State private var selectedGroupId: Int?
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("フィードURL") {
                    TextField("https://example.com/feed.xml", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("グループ（任意）") {
                    Picker("グループ", selection: $selectedGroupId) {
                        Text("なし").tag(Optional<Int>.none)
                        ForEach(groupStore.groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("フィードを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task { await addFeed() }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
            }
        }
    }

    private func addFeed() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            try await feedStore.createFeed(url: trimmed, groupId: selectedGroupId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddFeedView()
        .environmentObject(FeedStore())
        .environmentObject(GroupStore())
}
