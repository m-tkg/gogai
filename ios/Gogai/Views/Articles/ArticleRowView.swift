import SwiftUI

struct ArticleRowView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title ?? "（タイトルなし）")
                .font(.headline)
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .lineLimit(2)

            if let published = article.published_at {
                Text(published.displayDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let summary = article.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(article.isRead ? Color.clear : Color.accentColor.opacity(0.05))
    }
}

#Preview {
    ArticleRowView(article: Article(
        id: 1, feed_id: 1, guid: "guid", title: "記事タイトル",
        link: "https://example.com", summary: "要約テキスト", content: nil,
        published_at: "2024-01-01T12:00:00Z", is_read: 0, created_at: "2024-01-01T12:00:00Z",
        ai_summary: nil, ai_translation: nil
    ))
}
