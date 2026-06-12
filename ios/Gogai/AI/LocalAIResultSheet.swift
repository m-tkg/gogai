import SwiftUI

/// ローカル AI の要約・翻訳結果を表示する sheet。
/// 表示と同時に生成を開始し、結果はサーバーに保存しない。
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
            .task { await run() }
        }
    }

    private func run() async {
        guard let ai = LocalAI.makeArticleAI() else {
            errorMessage = "この端末ではローカル AI を利用できません（iOS 27 以上と Apple Intelligence の有効化が必要です）"
            return
        }
        do {
            let content = article.content ?? article.summary
            switch mode {
            case .summarize:
                result = try await ai.summarize(title: article.title, content: content)
            case .translateToJapanese:
                result = try await ai.translateToJapanese(title: article.title, content: content)
            }
        } catch LocalArticleAIError.emptyContent {
            errorMessage = "この記事には AI に渡せる本文がありません"
        } catch {
            errorMessage = "生成に失敗しました: \(error.localizedDescription)"
        }
    }
}
