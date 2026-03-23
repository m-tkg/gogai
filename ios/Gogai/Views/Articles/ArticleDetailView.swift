import SwiftUI
#if targetEnvironment(macCatalyst)
import WebKit
#endif

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
    #if targetEnvironment(macCatalyst)
    @StateObject private var macBrowser = BrowserModel()
    #endif

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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 8) {
                Button { showAISummary = true } label: {
                    Label("AI要約", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)

                Button { showAITranslation = true } label: {
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

    // MARK: - Article detail pane

    private var articleDetailPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(currentArticle.title ?? "（タイトルなし）")
                        .font(.title2)
                        .fontWeight(.bold)
                        .onLongPressGesture {
                            if let link = currentArticle.link, URL(string: link) != nil {
                                showShareSheet = true
                            }
                        }

                    if let published = currentArticle.published_at {
                        Label(published.displayDate, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    if let content = currentArticle.content ?? currentArticle.summary {
                        HTMLContentView(html: content, height: $contentHeight)
                            .frame(height: contentHeight)
                    } else {
                        Text("本文がありません")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .padding(.bottom, 16)
            }
            .id(currentArticle.id)

            Divider()
            bottomBar
        }
        .navigationTitle("記事")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let link = currentArticle.link, let url = URL(string: link) {
                    Button { showShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    #if targetEnvironment(macCatalyst)
                    Button { showBrowser = true } label: {
                        Image(systemName: "globe")
                    }
                    #endif
                    Button { openURL(url) } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        mainContent
            .sheet(isPresented: $showShareSheet) {
                if let link = currentArticle.link, let url = URL(string: link) {
                    ShareSheet(items: [url])
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

    @ViewBuilder
    private var mainContent: some View {
        #if targetEnvironment(macCatalyst)
        if showBrowser, let link = currentArticle.link, let url = URL(string: link) {
            BrowserWebView(model: macBrowser)
                .ignoresSafeArea()
                .navigationTitle(macBrowser.title.isEmpty ? (url.host() ?? "") : macBrowser.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("記事に戻る") { showBrowser = false }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { macBrowser.webView.goBack() } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!macBrowser.canGoBack)
                        Button { macBrowser.webView.goForward() } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!macBrowser.canGoForward)
                        Button {
                            if macBrowser.isLoading { macBrowser.webView.stopLoading() }
                            else { macBrowser.webView.reload() }
                        } label: {
                            Image(systemName: macBrowser.isLoading ? "xmark" : "arrow.clockwise")
                        }
                    }
                }
                .onAppear { macBrowser.webView.load(URLRequest(url: url)) }
        } else {
            articleDetailPane
        }
        #else
        articleDetailPane
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
            .sheet(isPresented: $showBrowser) {
                if let link = currentArticle.link, let url = URL(string: link) {
                    BrowserView(url: url)
                }
            }
        #endif
    }
}
