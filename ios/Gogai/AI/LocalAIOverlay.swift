import SwiftUI

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
                CircleIconButton(systemName: "xmark", accessibilityLabel: "閉じる", action: onClose)
            }
        }
    }

    private func button(for mode: LocalAIResultSheet.Mode) -> some View {
        CircleIconButton(systemName: mode.iconName, accessibilityLabel: mode.title) {
            onSelect(mode)
        }
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
