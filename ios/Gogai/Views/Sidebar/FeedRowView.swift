import SwiftUI

struct FeedRowView: View {
    let feed: Feed
    @Binding var selectedFeedId: Int?

    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var groupStore: GroupStore

    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    var body: some View {
        Button {
            selectedFeedId = feed.id
        } label: {
            HStack(spacing: 8) {
                if let faviconURL = feed.favicon_url, let url = URL(string: faviconURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().frame(width: 16, height: 16)
                    } placeholder: {
                        Image(systemName: "globe").frame(width: 16, height: 16)
                    }
                } else {
                    Image(systemName: "globe")
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                }
                Text(feed.title ?? feed.url)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .contextMenu {
            Button {
                showEditSheet = true
            } label: {
                Label("編集", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .confirmationDialog("フィードを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                Task {
                    try? await feedStore.deleteFeed(id: feed.id)
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }
}
