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
                await runFoundationModel(with: await loadSourceText())
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
            errorMessage = "この端末ではローカル AI を利用できません（iOS 27 以上と Apple Intelligence の有効化が必要です）"
            return
        }
        do {
            switch mode {
            case .summarize:
                result = try await ai.summarize(title: nil, content: text)
            case .translateToJapanese:
                result = try await ai.translateToJapanese(title: nil, content: text)
            }
        } catch LocalArticleAIError.emptyContent {
            errorMessage = "この記事には AI に渡せる本文がありません"
        } catch {
            errorMessage = "生成に失敗しました: \(error.localizedDescription)"
        }
    }
}

/// ローカル AI ボタン群（要約・翻訳）+ 任意の閉じるボタンのフローティング表示。
/// AI ボタンは LocalAI.isAvailable のときのみ、閉じるボタンは onClose 指定時のみ表示する。
struct LocalAIButtons: View {
    let onSelect: (LocalAIResultSheet.Mode) -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if LocalAI.isAvailable {
                button(for: .summarize)
                button(for: .translateToJapanese)
            }
            if let onClose {
                Button(action: onClose) {
                    circleIcon("xmark")
                }
                .accessibilityLabel("閉じる")
            }
        }
    }

    private func button(for mode: LocalAIResultSheet.Mode) -> some View {
        Button {
            onSelect(mode)
        } label: {
            circleIcon(mode.iconName)
        }
        .accessibilityLabel(mode.title)
    }

    private func circleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .frame(width: 48, height: 48)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.quaternary))
            .shadow(radius: 2, y: 1)
    }
}

/// 記事ページ（ブラウザ）の右下にローカル AI ボタン（+ 閉じるボタン）を重ね、結果を表示する modifier。
/// 翻訳はシステム翻訳選択時、レイアウト保持のページ内翻訳（TranslatedPageView）を開く。
private struct LocalAIOverlayModifier: ViewModifier {
    let article: Article
    let bottomPadding: CGFloat
    let onClose: (() -> Void)?

    @State private var mode: LocalAIResultSheet.Mode?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if LocalAI.isAvailable || onClose != nil {
                    LocalAIButtons(onSelect: { mode = $0 }, onClose: onClose)
                        .padding(.trailing, 16)
                        .padding(.bottom, bottomPadding)
                }
            }
            .sheet(item: $mode) { mode in
                sheetContent(for: mode)
            }
    }

    @ViewBuilder
    private func sheetContent(for mode: LocalAIResultSheet.Mode) -> some View {
        if mode == .translateToJapanese,
           case .translatedPage(let url) = TranslationDestination.forCurrentSettings(
               engine: TranslationEngine.current, link: article.link),
           #available(iOS 18.0, macCatalyst 26.0, *) {
            TranslatedPageView(url: url)
        } else {
            LocalAIResultSheet(article: article, mode: mode)
        }
    }
}

extension View {
    /// 画面右下にローカル AI（日本語要約・翻訳）ボタンを重ねる。
    /// onClose を渡すと翻訳ボタンの下に閉じるボタンも表示する。
    func localAIOverlay(for article: Article, bottomPadding: CGFloat = 16, onClose: (() -> Void)? = nil) -> some View {
        modifier(LocalAIOverlayModifier(article: article, bottomPadding: bottomPadding, onClose: onClose))
    }
}
