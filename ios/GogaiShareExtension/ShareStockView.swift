import SwiftUI

enum ShareUploadError: Error, LocalizedError {
    case noServerConfigured

    var errorDescription: String? {
        switch self {
        case .noServerConfigured:
            return "サーバー URL が設定されていません。本体アプリで設定してから共有してください。"
        }
    }
}

/// 共有シートから URL をストックする最小限の UI。
/// メモリ制限の厳しい拡張プロセス内では要約生成・WebKit を一切実行しない
/// (URL の保存のみ。サマリーは本体アプリが次回起動時に後追い生成する)。
struct ShareStockView: View {
    let url: URL
    let onFinish: () -> Void

    @State private var source = "共有"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("URL") {
                    Text(url.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Section("ストック元 / カテゴリ") {
                    TextField("例: 共有", text: $source)
                        .autocorrectionDisabled()
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("ストックに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onFinish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            guard let client = Self.makeClient() else { throw ShareUploadError.noServerConfigured }
            let trimmedSource = source.trimmingCharacters(in: .whitespaces)
            _ = try await StockRepository(client: client).create(
                url: url.absoluteString,
                source: trimmedSource.isEmpty ? nil : trimmedSource
            )
            onFinish()
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 共有 suite の resolvedServerURL(Gist 解決済みトンネル URL、または直接指定 URL)をそのまま使う。
    /// 拡張では Gist 再解決を行わない(失効していれば本体アプリを開いて再解決してもらう)。
    private static func makeClient() -> APIClient? {
        let defaults = AppGroup.defaults
        if let resolved = defaults.string(forKey: DefaultsKeys.resolvedServerURL), let url = URL(string: resolved) {
            return APIClient(baseURL: url)
        }
        if let raw = defaults.string(forKey: DefaultsKeys.serverURL), let url = URL(string: raw), url.host != "gist.github.com" {
            return APIClient(baseURL: url)
        }
        return nil
    }
}
