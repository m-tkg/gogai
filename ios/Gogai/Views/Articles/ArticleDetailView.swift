import SwiftUI

struct ArticleDetailView: View {
    let article: Article

    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.openURL) private var openURL

    private var isRead: Bool {
        articleStore.articles.first(where: { $0.id == article.id })?.isRead ?? article.isRead
    }

    @State private var showBrowser = false
    @State private var showAISummary = false
    @State private var showAITranslation = false
    @State private var contentHeight: CGFloat = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(article.title ?? "（タイトルなし）")
                    .font(.title2)
                    .fontWeight(.bold)

                // Meta
                HStack {
                    if let published = article.published_at {
                        Label(published.displayDate, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            if isRead {
                                await articleStore.markAsUnread(id: article.id)
                            } else {
                                await articleStore.markAsRead(id: article.id)
                            }
                        }
                    } label: {
                        Label(
                            isRead ? "未読にする" : "既読にする",
                            systemImage: isRead ? "envelope.badge" : "envelope.open"
                        )
                        .font(.caption)
                    }
                }

                Divider()

                // Content
                if let content = article.content ?? article.summary {
                    HTMLContentView(html: content, height: $contentHeight)
                        .frame(height: contentHeight)
                } else {
                    Text("本文がありません")
                        .foregroundStyle(.secondary)
                }

                Divider()

                // AI Actions
                HStack(spacing: 12) {
                    Button {
                        showAISummary = true
                    } label: {
                        Label("AI要約", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showAITranslation = true
                    } label: {
                        Label("AI翻訳", systemImage: "character.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("記事")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let link = article.link, let url = URL(string: link) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 80, coordinateSpace: .local)
                .onEnded { value in
                    let isUpSwipe = value.translation.height < -80
                        && abs(value.translation.width) < abs(value.translation.height) * 0.5
                    if isUpSwipe, let link = article.link, URL(string: link) != nil {
                        showBrowser = true
                    }
                }
        )
        .sheet(isPresented: $showBrowser) {
            if let link = article.link, let url = URL(string: link) {
                BrowserView(url: url)
            }
        }
        .sheet(isPresented: $showAISummary) {
            AISummaryView(article: article, action: .summarize)
        }
        .sheet(isPresented: $showAITranslation) {
            AISummaryView(article: article, action: .translate)
        }
        .onAppear {
            if !isRead {
                Task { await articleStore.markAsRead(id: article.id) }
            }
        }
    }
}
