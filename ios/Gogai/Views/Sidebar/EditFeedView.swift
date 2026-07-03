import SwiftUI

struct EditFeedView: View {
    let feed: Feed
    @EnvironmentObject private var feedStore: FeedStore

    @State private var titleText: String
    @State private var selectedGroupId: Int?

    init(feed: Feed) {
        self.feed = feed
        _titleText = State(initialValue: feed.title ?? "")
        _selectedGroupId = State(initialValue: feed.group_id)
    }

    var body: some View {
        FormSheet(
            title: "フィードを編集",
            confirmLabel: "保存",
            onSubmit: {
                let newTitle = titleText.trimmingCharacters(in: .whitespaces)
                try await feedStore.updateFeed(
                    id: feed.id,
                    title: newTitle.isEmpty ? nil : newTitle,
                    groupId: selectedGroupId
                )
            }
        ) {
            Section("タイトル") {
                TextField("フィード名", text: $titleText)
                    .autocorrectionDisabled()
            }

            GroupPickerSection(selectedGroupId: $selectedGroupId)
        }
    }
}
