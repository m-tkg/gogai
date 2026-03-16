import SwiftUI

@main
struct GogaiApp: App {
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
            .onChange(of: serverURLManager.serverURL) { _, newURL in
                guard let url = newURL else { return }
                let client = APIClient(baseURL: url)
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
            .onAppear {
                if let url = serverURLManager.serverURL {
                    let client = APIClient(baseURL: url)
                    groupStore.configure(with: client)
                    feedStore.configure(with: client, onRefreshComplete: {
                        Task { await articleStore.refresh() }
                    })
                    articleStore.configure(with: client)
                    settingsStore.configure(with: client)
                }
            }
        }
    }
}
