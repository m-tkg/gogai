import SwiftUI

struct EditFeedView: View {
    let feed: Feed
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var groupStore: GroupStore

    @State private var titleText: String
    @State private var selectedGroupId: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(feed: Feed) {
        self.feed = feed
        _titleText = State(initialValue: feed.title ?? "")
        _selectedGroupId = State(initialValue: feed.group_id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("タイトル") {
                    TextField("フィード名", text: $titleText)
                        .autocorrectionDisabled()
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
            .navigationTitle("フィードを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await saveFeed() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveFeed() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let newTitle = titleText.trimmingCharacters(in: .whitespaces)
        do {
            try await feedStore.updateFeed(
                id: feed.id,
                title: newTitle.isEmpty ? nil : newTitle,
                groupId: selectedGroupId
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
