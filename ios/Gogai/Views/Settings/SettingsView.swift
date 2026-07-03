import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @Environment(\.dismiss) private var dismiss

    @State private var retentionDaysText = ""
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var isCacheCleared = false
    @State private var cacheSize: Int64 = 0
    @State private var translationEngine = TranslationEngine.current
    #if targetEnvironment(macCatalyst)
    @State private var updater = UpdateChecker.shared
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("サーバーURL")
                        Spacer()
                        Text(serverURLManager.serverURL?.absoluteString ?? "未設定")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .lineLimit(1)
                    }

                    Button(role: .destructive) {
                        serverURLManager.clearServerURL()
                        dismiss()
                    } label: {
                        Text("サーバー設定をリセット")
                    }
                } header: {
                    Text("接続")
                }

                Section {
                    HStack {
                        Text("記事の保持期間")
                        Spacer()
                        TextField("180", text: $retentionDaysText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("日")
                    }

                    HStack {
                        Text("キャッシュサイズ")
                        Spacer()
                        Text(cacheSizeText)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        AppCache.shared.clearAll()
                        cacheSize = AppCache.shared.totalSize
                        isCacheCleared = true
                    } label: {
                        if isCacheCleared {
                            Label("キャッシュを削除しました", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        } else {
                            Text("ローカルキャッシュを削除")
                        }
                    }
                    .disabled(isCacheCleared)
                } header: {
                    Text("データ管理")
                } footer: {
                    Text("指定した日数より古い記事は自動的に削除されます。ローカルキャッシュを削除すると、次回起動時にサーバーから再取得します。")
                }

                if LocalAI.isAvailable {
                    Section {
                        Picker("翻訳エンジン", selection: $translationEngine) {
                            ForEach(TranslationEngine.allCases) { engine in
                                Text(engine.label).tag(engine)
                            }
                        }
                        .onChange(of: translationEngine) { _, newValue in
                            TranslationEngine.current = newValue
                        }
                    } header: {
                        Text("ローカル AI")
                    } footer: {
                        Text("「システム翻訳」はレイアウトを保ったまま記事ページ内の文字だけを翻訳します（翻訳専用モデル使用、初回は言語パックのダウンロードあり）。「ローカル AI」は訳文をテキストで表示します。要約は常にローカル AI を使用します。")
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError.localizedDescription)
                            .foregroundStyle(.red)
                    }
                }

                NavigationLink {
                    AdminView()
                } label: {
                    Label("管理", systemImage: "server.rack")
                }

                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("アプリ情報")
                }

                #if targetEnvironment(macCatalyst)
                updateSection
                #endif
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await saveSettings() }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                await settingsStore.fetchSettings()
                retentionDaysText = String(settingsStore.settings?.retention_days ?? 180)
                cacheSize = AppCache.shared.totalSize
            }
        }
    }

    private var cacheSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cacheSize)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    #if targetEnvironment(macCatalyst)
    @ViewBuilder
    private var updateSection: some View {
        Section {
            LabeledContent("現在のバージョン", value: updater.currentVersion)

            switch updater.state {
            case .idle, .failed:
                Button("アップデートを確認") { Task { await updater.check() } }
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("確認中…") }
            case .upToDate:
                Label("最新です", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Button("再確認") { Task { await updater.check() } }
            case .available(let release):
                Label("新しいバージョン \(release.tagName) があります", systemImage: "arrow.down.circle")
                Button("ダウンロードしてインストール") { Task { await updater.update(to: release) } }
            case .downloading:
                HStack { ProgressView().controlSize(.small); Text("ダウンロードして更新中…") }
            }

            if case .failed(let message) = updater.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("アップデート")
        } footer: {
            Text("GitHub のリリースから最新版を確認し、その場で更新します。更新後は自動で再起動します。")
        }
    }
    #endif

    private func saveSettings() async {
        guard let days = Int(retentionDaysText) else {
            saveError = APIError.invalidURL
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await settingsStore.updateRetentionDays(days)
            dismiss()
        } catch {
            saveError = error
        }
    }
}
