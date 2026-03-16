import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var isChecking = false
    @State private var isRestarting = false
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
                if let output = restartOutput {
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
                .disabled(isRestarting)
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
        defer { isRestarting = false }
        do {
            restartOutput = try await settingsStore.restart()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
