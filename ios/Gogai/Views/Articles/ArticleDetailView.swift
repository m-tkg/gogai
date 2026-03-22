import SwiftUI

struct ArticleDetailView: View {
    let article: Article

    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.openURL) private var openURL

    @State private var currentArticle: Article
    @State private var showBrowser = false
    @State private var showAISummary = false
    @State private var showAITranslation = false
    @State private var showShareSheet = false
    @State private var contentHeight: CGFloat = 200

    init(article: Article) {
        self.article = article
        self._currentArticle = State(initialValue: article)
    }

    private var isRead: Bool {
        articleStore.articles.first(where: { $0.id == currentArticle.id })?.isRead ?? currentArticle.isRead
    }

    private var navigableArticles: [Article] {
        articleStore.summaryOnly
            ? articleStore.articles.filter { $0.ai_summary != nil }
            : articleStore.articles
    }

    private var currentIndex: Int? {
        navigableArticles.firstIndex(where: { $0.id == currentArticle.id })
    }

    private var previousArticle: Article? {
        guard let idx = currentIndex, idx > 0 else { return nil }
        return navigableArticles[idx - 1]
    }

    private var nextArticle: Article? {
        guard let idx = currentIndex, idx < navigableArticles.count - 1 else { return nil }
        return navigableArticles[idx + 1]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(currentArticle.title ?? "（タイトルなし）")
                    .font(.title2)
                    .fontWeight(.bold)
                    .onLongPressGesture {
                        if let link = currentArticle.link, URL(string: link) != nil {
                            showShareSheet = true
                        }
                    }

                // Meta
                if let published = currentArticle.published_at {
                    Label(published.displayDate, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Content
                if let content = currentArticle.content ?? currentArticle.summary {
                    HTMLContentView(html: content, height: $contentHeight)
                        .frame(height: contentHeight)
                } else {
                    Text("本文がありません")
                        .foregroundStyle(.secondary)
                }

            }
            .padding()
        }
        .id(currentArticle.id)
        .navigationTitle("記事")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let link = currentArticle.link, let url = URL(string: link) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
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
                    if isUpSwipe, let link = currentArticle.link, URL(string: link) != nil {
                        showBrowser = true
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 8) {
                    Button {
                        showAISummary = true
                    } label: {
                        Label("AI要約", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showAITranslation = true
                    } label: {
                        Label("AI翻訳", systemImage: "character.bubble")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    Task {
                        if isRead {
                            await articleStore.markAsUnread(id: currentArticle.id)
                        } else {
                            await articleStore.markAsRead(id: currentArticle.id)
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isRead ? "envelope.badge" : "envelope.open")
                            .font(.title3)
                        Text(isRead ? "未読にする" : "既読にする")
                            .font(.caption2)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        if let prev = previousArticle { currentArticle = prev }
                    } label: {
                        Label("前の記事", systemImage: "chevron.up")
                    }
                    .disabled(previousArticle == nil)

                    Button {
                        if let next = nextArticle { currentArticle = next }
                    } label: {
                        Label("次の記事", systemImage: "chevron.down")
                    }
                    .disabled(nextArticle == nil)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(isPresented: $showShareSheet) {
            if let link = currentArticle.link, let url = URL(string: link) {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showBrowser) {
            if let link = currentArticle.link, let url = URL(string: link) {
                BrowserView(url: url)
            }
        }
        .sheet(isPresented: $showAISummary) {
            AISummaryView(article: currentArticle, action: .summarize)
        }
        .sheet(isPresented: $showAITranslation) {
            AISummaryView(article: currentArticle, action: .translate)
        }
        .onAppear {
            if !isRead {
                Task { await articleStore.markAsRead(id: currentArticle.id) }
            }
        }
        .onChange(of: currentArticle.id) { _, newId in
            contentHeight = 200
            showBrowser = false
            showAISummary = false
            showAITranslation = false
            showShareSheet = false
            Task {
                if let next = articleStore.articles.first(where: { $0.id == newId }), !next.isRead {
                    await articleStore.markAsRead(id: newId)
                }
            }
        }
    }
}
