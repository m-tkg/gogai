import SwiftUI
import Translation

/// ローカル AI の要約・翻訳結果を表示する sheet。
/// 表示と同時に生成を開始し、結果はサーバーに保存しない。
/// 翻訳は設定の TranslationEngine に応じて、基盤モデル（LLM）と
/// システム翻訳（Translation framework）を切り替える。
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

    private var usesTranslationFramework: Bool {
        mode == .translateToJapanese && TranslationEngine.current == .translationFramework
    }

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
                            Text(usesTranslationFramework ? "システム翻訳が処理しています…" : "オンデバイス AI が生成しています…")
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
            .background {
                // Translation framework は translationTask modifier 経由でしか
                // セッションを取得できないため、非表示ビューとして埋め込む
                if usesTranslationFramework, #available(iOS 18.0, macCatalyst 26.0, *) {
                    TranslationFrameworkRunner(
                        text: LocalArticleAI.preparePrompt(title: article.title, content: article.content ?? article.summary),
                        onResult: { result = $0 },
                        onError: { errorMessage = "システム翻訳に失敗しました: \($0.localizedDescription)" }
                    )
                }
            }
            .task {
                if !usesTranslationFramework {
                    await runFoundationModel()
                }
            }
        }
    }

    private func runFoundationModel() async {
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

/// ローカル AI ボタン群（要約・翻訳）のフローティング表示
struct LocalAIButtons: View {
    let onSelect: (LocalAIResultSheet.Mode) -> Void

    var body: some View {
        VStack(spacing: 12) {
            button(for: .summarize)
            button(for: .translateToJapanese)
        }
    }

    private func button(for mode: LocalAIResultSheet.Mode) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Image(systemName: mode.iconName)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.quaternary))
                .shadow(radius: 2, y: 1)
        }
        .accessibilityLabel(mode.title)
    }
}

/// 記事ページ（ブラウザ）の右下にローカル AI ボタンを重ね、結果 sheet を表示する modifier。
/// iOS 27 + Apple Intelligence 有効時のみボタンを表示する。
private struct LocalAIOverlayModifier: ViewModifier {
    let article: Article
    let bottomPadding: CGFloat

    @State private var mode: LocalAIResultSheet.Mode?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if LocalAI.isAvailable {
                    LocalAIButtons { mode = $0 }
                        .padding(.trailing, 16)
                        .padding(.bottom, bottomPadding)
                }
            }
            .sheet(item: $mode) { mode in
                LocalAIResultSheet(article: article, mode: mode)
            }
    }
}

extension View {
    /// 画面右下にローカル AI（日本語要約・翻訳）ボタンを重ねる
    func localAIOverlay(for article: Article, bottomPadding: CGFloat = 16) -> some View {
        modifier(LocalAIOverlayModifier(article: article, bottomPadding: bottomPadding))
    }
}

/// Translation framework（システム翻訳）の実行用 hidden view。
/// translationTask は SwiftUI modifier としてのみ提供されるため、
/// 翻訳設定をセットしてセッションを受け取る役だけを担う。
@available(iOS 18.0, macCatalyst 26.0, *)
private struct TranslationFrameworkRunner: View {
    let text: String
    let onResult: (String) -> Void
    let onError: (Error) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                // Why: TranslationSession は non-Sendable で、MainActor 隔離のクロージャから
                // await 越しに使うと Swift 6 の region isolation エラーになる。
                // このクロージャ内でしか session を使わず逐次アクセスのみのため unsafe 束縛で回避する。
                nonisolated(unsafe) let session = session
                do {
                    let response = try await session.translate(text)
                    onResult(response.targetText)
                } catch {
                    onError(error)
                }
            }
            .onAppear {
                guard !text.isEmpty else {
                    onError(LocalArticleAIError.emptyContent)
                    return
                }
                // 翻訳元は自動判定、翻訳先は日本語
                configuration = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: "ja")
                )
            }
    }
}
