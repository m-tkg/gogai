import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var serverURLManager: ServerURLManager
    @Environment(\.dismiss) private var dismiss

    @State private var retentionDaysText = ""
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var isCacheCleared = false

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

                    Button(role: .destructive) {
                        AppCache.shared.clearAll()
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
                    Text("指定した日数より古い記事は自動的に削除されます。ローカルキャッシュを削除すると次回起動時に再取得します。")
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
            }
        }
    }

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
