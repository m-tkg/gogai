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

    var body: some View {
        SwiftUI.Group {
            if isIPad {
                NavigationSplitView {
                    SidebarView(
                        selectedFeedId: $selectedFeedId,
                        selectedGroupId: $selectedGroupId
                    )
                } content: {
                    ArticleListView(
                        feedId: selectedFeedId,
                        groupId: selectedGroupId,
                        selectedArticle: $selectedArticle
                    )
                } detail: {
                    if let article = selectedArticle {
                        ArticleDetailView(article: article)
                            .id(article.id)
                    } else {
                        ContentUnavailableView("記事を選択", systemImage: "newspaper")
                    }
                }
                .onChange(of: selectedFeedId) { selectedArticle = nil }
                .onChange(of: selectedGroupId) { selectedArticle = nil }
            } else {
                NavigationStack(path: $navigationPath) {
                    SidebarView(
                        selectedFeedId: $selectedFeedId,
                        selectedGroupId: $selectedGroupId,
                        onNavigate: { dest in navigationPath.append(dest) }
                    )
                    .navigationDestination(for: ArticleDestination.self) { dest in
                        ArticleListView(
                            feedId: dest.feedId,
                            groupId: dest.groupId,
                            selectedArticle: $selectedArticle,
                            onArticleSelected: { article in navigationPath.append(article) }
                        )
                        .navigationDestination(for: Article.self) { article in
                            ArticleDetailView(article: article)
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
