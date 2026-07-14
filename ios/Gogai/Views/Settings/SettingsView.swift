import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @Environment(\.dismiss) private var dismiss

    @State private var retentionDaysText = ""
    @State private var adminSecretText = ""
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var isCacheCleared = false
    @State private var cacheSize: Int64 = 0
    @State private var translationEngine = TranslationEngine.current
    @State private var aiProvider = AIProvider.current
    @State private var openAIAPIKeyText = ""
    @State private var geminiAPIKeyText = ""
    @State private var claudeAPIKeyText = ""

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

                Section {
                    Picker("使用するAI", selection: $aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    SecureField("OpenAI APIキー", text: $openAIAPIKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Gemini APIキー", text: $geminiAPIKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Claude APIキー", text: $claudeAPIKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("ページ翻訳", selection: $translationEngine) {
                        ForEach(TranslationEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("自動は OpenAI、Gemini、Claude の順に API キーがある外部 AI を使い、未設定ならオンデバイスを使います。ページ翻訳で「システム翻訳」を選ぶと、記事ページ内の文字だけを翻訳します。要約はここで選んだ AI を使用します。")
                }

                if let saveError {
                    Section {
                        Text(saveError.localizedDescription)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    SecureField("未設定", text: $adminSecretText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("管理者シークレット")
                } footer: {
                    Text("「管理」画面の操作を保護します。サーバー側の ADMIN_SECRET 環境変数と同じ値を入力してください(サーバー側が未設定の場合は空のままで動作します)。")
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
                adminSecretText = KeychainStore.get(forKey: KeychainStore.adminSecretKey) ?? ""
                aiProvider = AIProvider.current
                translationEngine = TranslationEngine.current
                openAIAPIKeyText = KeychainStore.get(forKey: KeychainStore.openAIAPIKey) ?? ""
                geminiAPIKeyText = KeychainStore.get(forKey: KeychainStore.geminiAPIKey) ?? ""
                claudeAPIKeyText = KeychainStore.get(forKey: KeychainStore.claudeAPIKey) ?? ""
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

    private func saveSettings() async {
        guard let days = Int(retentionDaysText) else {
            saveError = APIError.invalidURL
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let trimmedSecret = adminSecretText.trimmingCharacters(in: .whitespaces)
        KeychainStore.set(trimmedSecret.isEmpty ? nil : trimmedSecret, forKey: KeychainStore.adminSecretKey)
        AIProvider.current = aiProvider
        TranslationEngine.current = translationEngine
        saveAPIKey(openAIAPIKeyText, forKey: KeychainStore.openAIAPIKey)
        saveAPIKey(geminiAPIKeyText, forKey: KeychainStore.geminiAPIKey)
        saveAPIKey(claudeAPIKeyText, forKey: KeychainStore.claudeAPIKey)
        do {
            try await settingsStore.updateRetentionDays(days)
            dismiss()
        } catch {
            saveError = error
        }
    }

    private func saveAPIKey(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.set(trimmed.isEmpty ? nil : trimmed, forKey: key)
    }
}
