import SwiftUI

struct ArticleRowView: View {
    let article: Article

    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var groupStore: GroupStore

    private var feed: Feed? {
        feedStore.feeds.first(where: { $0.id == article.feed_id })
    }

    private var faviconURL: URL? {
        feed.flatMap { URL(string: $0.favicon_url ?? "") }
    }

    private var groupName: String? {
        guard let groupId = feed?.group_id else { return nil }
        return groupStore.groups.first(where: { $0.id == groupId })?.name
    }

    @State private var showShareSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            faviconView
                .frame(width: 16, height: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "（タイトルなし）")
                    .font(.headline)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)
                    .onLongPressGesture {
                        if article.link != nil { showShareSheet = true }
                    }

                if let published = article.published_at {
                    HStack(spacing: 4) {
                        if let name = groupName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(published.displayDate)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let summary = article.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
            VStack(spacing: 4) {
                if articleStore.summarizingIds.contains(article.id) {
                    ProgressView()
                } else if article.ai_summary != nil {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .font(.caption)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .listRowBackground(article.isRead ? Color.clear : Color.accentColor.opacity(0.05))
        .sheet(isPresented: $showShareSheet) {
            if let link = article.link, let url = URL(string: link) {
                ShareSheet(items: [url])
            }
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let url = faviconURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "globe").foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ArticleRowView(article: Article(
        id: 1, feed_id: 1, guid: "guid", title: "記事タイトル",
        link: "https://example.com", summary: "要約テキスト", content: nil,
        published_at: "2024-01-01T12:00:00Z", is_read: 0, created_at: "2024-01-01T12:00:00Z",
        ai_summary: nil, ai_translation: nil, read_at: nil
    ))
    .environmentObject(FeedStore())
    .environmentObject(ArticleStore())
    .environmentObject(GroupStore())
}
