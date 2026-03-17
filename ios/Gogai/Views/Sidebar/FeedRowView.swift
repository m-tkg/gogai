import SwiftUI

struct FeedRowView: View {
    let feed: Feed
    @Binding var selectedFeedId: Int?
    var onNavigate: ((ArticleDestination) -> Void)?

    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var articleStore: ArticleStore

    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    var body: some View {
        Button {
            selectedFeedId = feed.id
            onNavigate?(ArticleDestination(feedId: feed.id, groupId: nil))
        } label: {
            HStack(spacing: 8) {
                let faviconURL = feed.favicon_url.flatMap { URL(string: $0) }
                AsyncImage(url: faviconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 16, height: 16)
                Text(feed.title ?? feed.url)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                let unread = articleStore.unreadCount(for: feed.id)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
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
        .sheet(isPresented: $showEditSheet) {
            EditFeedView(feed: feed)
                .environmentObject(feedStore)
                .environmentObject(groupStore)
        }
    }
}
