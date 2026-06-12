import SwiftUI

struct AddFeedView: View {
    @EnvironmentObject private var feedStore: FeedStore

    @State private var urlText = ""
    @State private var selectedGroupId: Int?

    var body: some View {
        FormSheet(
            title: "フィードを追加",
            confirmLabel: "追加",
            confirmDisabled: urlText.trimmingCharacters(in: .whitespaces).isEmpty,
            onSubmit: {
                let trimmed = urlText.trimmingCharacters(in: .whitespaces)
                try await feedStore.createFeed(url: trimmed, groupId: selectedGroupId)
            }
        ) {
            Section("フィードURL") {
                TextField("https://example.com/feed.xml", text: $urlText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            GroupPickerSection(selectedGroupId: $selectedGroupId)
        }
    }
}

#Preview {
    AddFeedView()
        .environmentObject(FeedStore())
        .environmentObject(GroupStore())
}
