import SwiftUI

/// アプリのトップレベルビュー。実際のナビゲーション状態・プラットフォーム別レイアウトは
/// ArticleNavigationRootView(記事閲覧)が持つ(RootView は起動時フェッチのみを担う)。
struct RootView: View {
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore

    var body: some View {
        ArticleNavigationRootView()
            .task {
                await groupStore.fetchGroups()
                await feedStore.fetchFeeds()
                await articleStore.fetchArticles()
            }
    }
}
