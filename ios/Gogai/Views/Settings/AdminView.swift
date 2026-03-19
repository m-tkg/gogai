import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var articleStore: ArticleStore

    @State private var isChecking = false
    @State private var isWaitingForRestart = false
    @State private var restartPhase: RestartPhase = .building
    @State private var restartCheckCount = 0
    @State private var restartOutput: String?
    @State private var errorMessage: String?

    private enum RestartPhase {
        case building   // git pull + npm build 中
        case waiting    // サーバー再起動待ち（ポーリング中）
    }

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
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(restartPhase == .building
                             ? "git pull・ビルド中..."
                             : "再起動中... (\(restartCheckCount)回目の確認)")
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
                    Text("git pull して再起動")
                }
                .disabled(isWaitingForRestart)
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
        // ボタンを押した瞬間から「git pull・ビルド中...」を表示
        restartPhase = .building
        restartCheckCount = 0
        isWaitingForRestart = true
        errorMessage = nil
        do {
            restartOutput = try await settingsStore.restart()
        } catch {
            isWaitingForRestart = false
            errorMessage = error.localizedDescription
            return
        }

        // レスポンスが返ったらサーバー再起動待ちフェーズへ
        restartPhase = .waiting
        await waitForServer()
        isWaitingForRestart = false

        // サーバーが戻ったら全ストアを再フェッチ（接続を復活させる）
        await groupStore.fetchGroups()
        await feedStore.fetchFeeds()
        await articleStore.fetchArticles()
        await settingsStore.checkUpdate()
    }

    /// /health に到達できるまで 1 秒間隔で最大 120 回（約 2 分）ポーリングする
    /// URLSession.shared の stale コネクションを避けるため ephemeral セッションを使用
    @MainActor
    private func waitForServer() async {
        // resolvedURL（Gist URL 解決済みの実際のサーバー URL）を使う
        guard let baseURL = serverURLManager.resolvedURL else { return }
        let healthURL = baseURL.appendingPathComponent("health")
        let config = URLSessionConfiguration.ephemeral
        // 応答待ちはタイムアウトを短くして素早くリトライ
        config.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: config)
        for _ in 0..<120 {
            try? await Task.sleep(for: .seconds(1))
            restartCheckCount += 1
            if let (_, response) = try? await session.data(from: healthURL),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
        }
    }
}
