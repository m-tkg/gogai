import SwiftUI

/// ローカル AI（基盤モデル）の要約・翻訳結果を表示する sheet。
/// 表示と同時に生成を開始し、結果はサーバーに保存しない。
/// システム翻訳（Translation framework）選択時のページ内翻訳は TranslatedPageView が担う。
struct LocalAIResultSheet: View {
    enum Mode: String, Identifiable {
        case summarize
        case translateToJapanese

        var id: String { rawValue }

        var title: String {
            switch self {
            case .summarize: return "日本語で要約"
            case .translateToJapanese: return "日本語に翻訳"
            }
        }

        var iconName: String {
            switch self {
            case .summarize: return "sparkles"
            case .translateToJapanese: return "character.bubble"
            }
        }
    }

    let article: Article
    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var result: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let result {
                        Text(result)
                            .font(.body)
                            .textSelection(.enabled)
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("オンデバイス AI が生成しています…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                // 生成中にバックグラウンドへ移っても継続する（システム猶予内）
                await BackgroundExecution.run(name: "LocalAI.generate") {
                    await runFoundationModel(with: await loadSourceText())
                }
            }
        }
    }

    /// AI に渡す本文を用意する。
    /// 記事ページ（article.link）の本文を優先し、取得できない場合は RSS の本文にフォールバックする。
    private func loadSourceText() async -> String {
        if let link = article.link, let url = URL(string: link),
           let pageText = try? await ArticleContentFetcher.fetchPlainText(from: url),
           !pageText.isEmpty {
            return LocalArticleAI.preparePrompt(title: article.title, content: pageText)
        }
        return LocalArticleAI.preparePrompt(title: article.title, content: article.content ?? article.summary)
    }

    private func runFoundationModel(with text: String) async {
        guard let ai = LocalAI.makeArticleAI() else {
            errorMessage = LocalAIError.aiUnavailable.errorDescription
            return
        }
        do {
            switch mode {
            case .summarize:
                result = try await ai.summarize(title: nil, content: text)
            case .translateToJapanese:
                // 同じ本文の訳は1週間ローカルキャッシュから返す
                if let cached = TranslationCache.shared.target(for: text, engine: .foundationModel) {
                    result = cached
                    return
                }
                let translated = try await ai.translateToJapanese(title: nil, content: text)
                TranslationCache.shared.store(source: text, target: translated, engine: .foundationModel)
                TranslationCache.shared.persist()
                result = translated
            }
        } catch LocalAIError.emptyContent {
            errorMessage = "この記事には AI に渡せる本文がありません"
        } catch {
            errorMessage = "生成に失敗しました: \(error.localizedDescription)"
        }
    }
}
