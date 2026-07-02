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
            // Why: initial: true で init 時のキャッシュ復元値（前回トンネル URL）でも
            // 起動直後に configureStores() を走らせる。これがないと resolve() が
            // 同じ URL を返した場合に値変化として検知されず、Store の client が nil のまま。
            .onChange(of: serverURLManager.resolvedURL, initial: true) { _, newURL in
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
        // Why: 接続失敗（トンネル URL 失効など）を検知したら ServerURLManager に再解決を促す。
        // デバウンス + resolve 成功時の onChange により自動回復する。
        let client = APIClient(baseURL: baseURL, onNetworkFailure: { [weak serverURLManager] in
            Task { await serverURLManager?.reportFailure() }
        })
        groupStore.configure(with: client)
        feedStore.configure(with: client, onRefreshComplete: {
            Task { await articleStore.refresh() }
        })
        articleStore.configure(with: client)
        settingsStore.configure(with: client)
        // Why: 3 本は独立した API のため並列化で起動時の総待ち時間を短縮する。
        // async let や withTaskGroup は Store が non-Sendable のため使えない
        // （Store は @MainActor 宣言なしでクラスレベル sendable でない）。
        // 代わりに @MainActor な Task を 3 つ投げて並列実行する。
        Task { @MainActor in await groupStore.fetchGroups() }
        Task { @MainActor in await feedStore.fetchFeeds() }
        Task { @MainActor in
            await articleStore.fetchArticles()
            // バッジ用のサーバー集計（シークレット込み・1 リクエスト）を最新化する
            await articleStore.refreshCounts()
        }
    }
}
