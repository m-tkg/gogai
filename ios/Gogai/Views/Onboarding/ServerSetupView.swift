import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var serverURLManager: ServerURLManager

    @State private var urlText = "http://192.168.1.1:3040"
    @State private var isChecking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.1:3040", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("サーバーURL")
                } footer: {
                    Text("gogaiバックエンドのURLを入力してください（例: http://192.168.1.1:3040）")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isChecking {
                                ProgressView()
                            } else {
                                Text("接続する")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isChecking || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("サーバー設定")
        }
    }

    private func connect() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed) else {
            errorMessage = "無効なURLです"
            return
        }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            // Gist URL の場合はコンテンツから実 URL を解決してからヘルスチェック
            let resolved = try await ServerURLManager.resolveURL(url)
            let healthURL = resolved.appendingPathComponent("health")
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "サーバーに接続できませんでした"
                return
            }
            // 元の URL（Gist URL）を保存することで、次回起動時に最新 URL を再取得できる
            serverURLManager.setServerURL(url)
        } catch {
            errorMessage = "接続失敗: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ServerSetupView()
        .environmentObject(ServerURLManager())
}
