import SwiftUI

@main
struct GogaiApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var serverURLManager = ServerURLManager()
    @StateObject private var groupStore = GroupStore()
    @StateObject private var feedStore = FeedStore()
    @StateObject private var articleStore = ArticleStore()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            SwiftUI.Group {
                if serverURLManager.isConfigured {
                    RootView()
                } else {
                    ServerSetupView()
                }
            }
            .environmentObject(serverURLManager)
            .environmentObject(groupStore)
            .environmentObject(feedStore)
            .environmentObject(articleStore)
            .environmentObject(settingsStore)
            // serverURL が変わったら再解決（Gist URL → 実 URL）
            .onChange(of: serverURLManager.serverURL) { _, _ in
                Task { await serverURLManager.resolve() }
            }
            // resolvedURL が確定したら API クライアントを設定してデータを取得
            .onChange(of: serverURLManager.resolvedURL) { _, newURL in
                guard let url = newURL else { return }
                configureStores(baseURL: url)
            }
            // バックグラウンドから復帰したら最新記事を取得
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, serverURLManager.resolvedURL != nil else { return }
                Task { await articleStore.refresh() }
            }
            // 起動時に解決（Gist URL の場合は Gist から最新 URL を取得）
            .task {
                await serverURLManager.resolve()
            }
            // 5分ごとに記事を自動更新（resolvedURL が変わるとタスクが再起動される）
            .task(id: serverURLManager.resolvedURL) {
                guard serverURLManager.resolvedURL != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(300))
                    guard !Task.isCancelled else { break }
                    await articleStore.refresh()
                }
            }
        }
    }

    private func configureStores(baseURL: URL) {
        let client = APIClient(baseURL: baseURL)
        groupStore.configure(with: client)
        feedStore.configure(with: client, onRefreshComplete: {
            Task { await articleStore.refresh() }
        })
        articleStore.configure(with: client)
        settingsStore.configure(with: client)
        Task {
            await groupStore.fetchGroups()
            await feedStore.fetchFeeds()
            await articleStore.fetchArticles()
        }
    }
}
