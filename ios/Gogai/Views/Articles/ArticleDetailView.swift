import SwiftUI
#if targetEnvironment(macCatalyst)
import WebKit
#endif

/// 既読/お気に入りトグルと前後記事ナビゲーションのバー
private struct ArticleDetailBottomBar: View {
    let isRead: Bool
    let isFavorite: Bool
    let previousArticle: Article?
    let nextArticle: Article?
    let onToggleRead: () async -> Void
    let onToggleFavorite: () async -> Void
    let onNavigate: (Article) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Spacer()

            HStack(spacing: 24) {
                Button {
                    Task { await onToggleRead() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isRead ? "envelope.badge" : "envelope.open")
                            .font(.title3)
                        Text(isRead ? "未読にする" : "既読にする")
                            .font(.caption2)
                    }
                }

                Button {
                    Task { await onToggleFavorite() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isFavorite ? "star.slash" : "star")
                            .font(.title3)
                        Text(isFavorite ? "お気に入り解除" : "お気に入り")
                            .font(.caption2)
                    }
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    if let prev = previousArticle { onNavigate(prev) }
                } label: {
                    Label("前の記事", systemImage: "chevron.up")
                }
                .disabled(previousArticle == nil)

                Button {
                    if let next = nextArticle { onNavigate(next) }
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
}

struct ArticleDetailView: View {
    let article: Article

    @EnvironmentObject private var articleStore: ArticleStore
    @EnvironmentObject private var feedStore: FeedStore
    @Environment(\.openURL) private var openURL

    @State private var currentArticle: Article
    @State private var showBrowser = false
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

    private var isFavorite: Bool {
        articleStore.articles.first(where: { $0.id == currentArticle.id })?.isFavorite ?? currentArticle.isFavorite
    }

    private var navigableArticles: [Article] {
        articleStore.articles
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
        ArticleDetailBottomBar(
            isRead: isRead,
            isFavorite: isFavorite,
            previousArticle: previousArticle,
            nextArticle: nextArticle,
            onToggleRead: {
                // Why: currentArticle はナビゲーション用のスナップショットで古い可能性が
                // あるため、store 由来の isRead で分岐する（toggleRead は使わない）
                if isRead {
                    await articleStore.markAsUnread(id: currentArticle.id)
                } else {
                    await articleStore.markAsRead(id: currentArticle.id)
                }
            },
            onToggleFavorite: {
                if isFavorite {
                    await articleStore.unfavorite(id: currentArticle.id)
                } else {
                    await articleStore.favorite(id: currentArticle.id)
                }
            },
            onNavigate: { currentArticle = $0 }
        )
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

    // MARK: - Browser destination（記事ページ）

    #if !targetEnvironment(macCatalyst)
    @ViewBuilder
    private var browserDestination: some View {
        if let link = currentArticle.link, let url = URL(string: link) {
            // 記事ページ右下にローカル AI ボタン + 閉じるボタンを表示
            // （SFSafariViewController の下部ツールバーを避けて持ち上げる）
            BrowserView(url: url)
                .localAIOverlay(for: currentArticle, bottomPadding: 70, onClose: { showBrowser = false })
                .toolbar(.hidden, for: .navigationBar)
                // 閉じる操作は右スワイプ（開く操作の左スワイプと対）
                .simultaneousGesture(
                    DragGesture(minimumDistance: 80, coordinateSpace: .local)
                        .onEnded { value in
                            let isRightSwipe = value.translation.width > 80
                                && abs(value.translation.height) < abs(value.translation.width) * 0.5
                            if isRightSwipe {
                                showBrowser = false
                            }
                        }
                )
        }
    }
    #endif

    // MARK: - Body

    var body: some View {
        mainContent
            .sheet(isPresented: $showShareSheet) {
                if let link = currentArticle.link, let url = URL(string: link) {
                    ShareSheet(items: [url])
                }
            }
            .onAppear {
                if !isRead {
                    Task { await articleStore.markAsRead(id: currentArticle.id) }
                }
            }
            .onChange(of: currentArticle.id) { _, newId in
                contentHeight = 200
                showBrowser = false
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
                .localAIOverlay(for: currentArticle)
        } else {
            articleDetailPane
        }
        #else
        articleDetailPane
            .simultaneousGesture(
                DragGesture(minimumDistance: 80, coordinateSpace: .local)
                    .onEnded { value in
                        // 左スワイプで記事ページを開く
                        // （縦成分が大きい場合はスクロールとみなして発火させない）
                        let isLeftSwipe = value.translation.width < -80
                            && abs(value.translation.height) < abs(value.translation.width) * 0.5
                        if isLeftSwipe, let link = currentArticle.link, URL(string: link) != nil {
                            showBrowser = true
                        }
                    }
            )
            // 記事ページは sheet（下から）ではなく push 遷移（右から左）で表示する
            .navigationDestination(isPresented: $showBrowser) {
                browserDestination
            }
        #endif
    }
}
