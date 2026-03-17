import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore

    @State private var isChecking = false
    @State private var isRestarting = false
    @State private var isWaitingForRestart = false
    @State private var restartOutput: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if let updateCheck = settingsStore.updateCheck {
                    HStack {
                        Text("ローカル")
                        Spacer()
                        Text(updateCheck.local)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("リモート")
                        Spacer()
                        Text(updateCheck.remote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("アップデート")
                        Spacer()
                        if updateCheck.hasUpdate {
                            Label("あり", systemImage: "arrow.up.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("最新版")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    Task { await checkUpdate() }
                } label: {
                    HStack {
                        if isChecking { ProgressView() }
                        Text("アップデートを確認")
                    }
                }
                .disabled(isChecking)
            } header: {
                Text("アップデート")
            }

            Section {
                if isWaitingForRestart {
                    HStack {
                        ProgressView()
                        Text("再起動中...")
                            .foregroundStyle(.secondary)
                    }
                } else if let output = restartOutput {
                    Text(output)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    Task { await restart() }
                } label: {
                    HStack {
                        if isRestarting { ProgressView() }
                        Text("git pull して再起動")
                    }
                }
                .disabled(isRestarting || isWaitingForRestart)
            } header: {
                Text("再起動")
            } footer: {
                Text("サーバー上で git pull を実行した後、サービスを再起動します")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("管理")
        .task {
            await settingsStore.checkUpdate()
        }
    }

    private func checkUpdate() async {
        isChecking = true
        defer { isChecking = false }
        await settingsStore.checkUpdate()
        if let error = settingsStore.error {
            errorMessage = error.localizedDescription
        }
    }

    private func restart() async {
        isRestarting = true
        errorMessage = nil
        do {
            restartOutput = try await settingsStore.restart()
        } catch {
            isRestarting = false
            errorMessage = error.localizedDescription
            return
        }
        isRestarting = false

        // サーバーが再起動して戻るまでポーリング
        isWaitingForRestart = true
        await waitForServer()
        isWaitingForRestart = false

        // サーバーが戻ったら全ストアを再フェッチ（接続を復活させる）
        await groupStore.fetchGroups()
        await feedStore.fetchFeeds()
        await articleStore.fetchArticles()
    }

    /// /health に到達できるまで 3 秒間隔で最大 40 回（約 2 分）ポーリングする
    /// URLSession.shared の stale コネクションを避けるため ephemeral セッションを使用
    private func waitForServer() async {
        guard let baseURL = serverURLManager.serverURL else { return }
        let healthURL = baseURL.appendingPathComponent("health")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            if let (_, response) = try? await session.data(from: healthURL),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
        }
    }
}
