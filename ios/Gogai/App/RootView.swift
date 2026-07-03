import SwiftUI

struct RootView: View {
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore

    @State private var selectedFeedId: Int?
    @State private var selectedGroupId: Int?
    @State private var selectedArticle: Article?
    @State private var navigationPath = NavigationPath()
    @State private var showStocks = false

    var body: some View {
        SwiftUI.Group {
            if isIPad {
                NavigationSplitView {
                    SidebarView(
                        selectedFeedId: $selectedFeedId,
                        selectedGroupId: $selectedGroupId,
                        onStockTap: { showStocks = true }
                    )
                } content: {
                    ArticleListView(
                        feedId: selectedFeedId,
                        groupId: selectedGroupId,
                        selectedArticle: $selectedArticle
                    )
                } detail: {
                    // Why: navigationDestination(isPresented:) による記事ページ（BrowserView）への
                    // push は NavigationStack が必須。detail カラムに直接置くと push 先がなく、
                    // 概要ページの左スワイプが何も起こさない
                    NavigationStack {
                        if let article = selectedArticle {
                            ArticleDetailView(article: article)
                                .id(article.id)
                        } else {
                            ContentUnavailableView("記事を選択", systemImage: "newspaper")
                        }
                    }
                }
                .onChange(of: selectedFeedId) { selectedArticle = nil }
                .onChange(of: selectedGroupId) { selectedArticle = nil }
                .fullScreenCover(isPresented: $showStocks) {
                    NavigationStack {
                        StockCategoryListView(isModal: true)
                            .navigationDestination(for: StockCategory.self) { category in
                                StockListView(category: category)
                                    .navigationDestination(for: Stock.self) { stock in
                                        StockDetailView(stock: stock)
                                    }
                            }
                    }
                }
            } else {
                NavigationStack(path: $navigationPath) {
                    SidebarView(
                        selectedFeedId: $selectedFeedId,
                        selectedGroupId: $selectedGroupId,
                        onNavigate: { dest in navigationPath.append(dest) },
                        onStockTap: { navigationPath.append(StockDestination()) }
                    )
                    .navigationDestination(for: ArticleDestination.self) { dest in
                        ArticleListView(
                            feedId: dest.feedId,
                            groupId: dest.groupId,
                            selectedArticle: $selectedArticle,
                            onArticleSelected: { article in navigationPath.append(article) },
                            onStockTap: { navigationPath.append(StockDestination()) }
                        )
                        .navigationDestination(for: Article.self) { article in
                            ArticleDetailView(article: article)
                        }
                    }
                    .navigationDestination(for: StockDestination.self) { _ in
                        StockCategoryListView()
                            .navigationDestination(for: StockCategory.self) { category in
                                StockListView(category: category)
                                    .navigationDestination(for: Stock.self) { stock in
                                        StockDetailView(stock: stock)
                                    }
                            }
                    }
                }
            }
        }
        .task {
            await groupStore.fetchGroups()
            await feedStore.fetchFeeds()
            await articleStore.fetchArticles()
        }
    }

    private var isIPad: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }
}

struct ArticleDestination: Hashable {
    let feedId: Int?
    let groupId: Int?
}

/// ストック一覧への遷移マーカー(パラメータなし)
struct StockDestination: Hashable {}
