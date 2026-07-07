import SwiftUI

/// 記事閲覧(フィード/グループ選択・記事一覧・記事概要)のナビゲーション状態と
/// プラットフォーム別のビュー構成(iPad: NavigationSplitView、iPhone: NavigationStack)を持つ。
///
/// Stock 機能へのトリガー(showStocks の切り替え・StockDestination の push)は
/// ここで受け持つが、Stock 側の実際のビュー構成(カテゴリ一覧以下)は一切知らず、
/// StockRootView に委譲する。
///
/// 注記: iPhone は SidebarView 1画面から記事一覧・ストックの両方へ遷移できる UX のため、
/// NavigationStack(と navigationPath)は記事・ストック両方の destination を1つの
/// スタックで管理する(SwiftUI の NavigationStack は画面ごとに1つが基本のため、
/// ここを完全に2つの独立したビューへ分割すると UX 自体の変更になってしまう)。
/// そのため「記事閲覧専用」と「ストック専用」を完全に分離した2つのトップレベルビューを
/// 並べる形にはせず、記事側がナビゲーションコンテナ(NavigationStack/NavigationSplitView)を
/// 持ちつつ、コンテンツの中身だけを StockRootView に委ねる形にしている。
struct ArticleNavigationRootView: View {
    @State private var selectedFeedId: Int?
    @State private var selectedGroupId: Int?
    @State private var selectedArticle: Article?
    @State private var navigationPath = NavigationPath()
    @State private var showStocks = false

    var body: some View {
        SwiftUI.Group {
            if isIPad {
                iPadBody
            } else {
                iPhoneBody
            }
        }
    }

    private var iPadBody: some View {
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
                StockRootView(isModal: true)
            }
        }
    }

    private var iPhoneBody: some View {
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
                StockRootView()
            }
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
