import SwiftUI

/// ページ内翻訳(TranslatedPageModel)の右下フローティングボタン群。
/// 上: 原文 ⇄ 訳文トグル(常時表示、翻訳完了まで無効)/ 中: engine 固有の追加ボタン(任意、再翻訳など)/
/// 下: 閉じる。システム翻訳(TranslatedPageView)・基盤モデル翻訳(FMTranslatedPageView)の両方が使う。
struct PageTranslationFloatingButtons<ExtraButtons: View>: View {
    @ObservedObject var model: TranslatedPageModel
    let onClose: () -> Void
    @ViewBuilder var extraButtons: () -> ExtraButtons

    /// 原文/翻訳トグルは翻訳が完了し、訳が1件以上あるときだけ操作可能
    private var isToggleEnabled: Bool {
        model.status == .done && model.hasTranslations
    }

    var body: some View {
        VStack(spacing: 12) {
            CircleIconButton(
                systemName: model.isShowingOriginal ? "character.bubble" : "doc.plaintext",
                accessibilityLabel: model.isShowingOriginal ? "翻訳を表示" : "原文を表示",
                isEnabled: isToggleEnabled
            ) {
                Task {
                    if model.isShowingOriginal {
                        await model.showTranslation()
                    } else {
                        await model.showOriginal()
                    }
                }
            }
            extraButtons()
            CircleIconButton(systemName: "xmark", accessibilityLabel: "閉じる", action: onClose)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 70)
    }
}

extension PageTranslationFloatingButtons where ExtraButtons == EmptyView {
    init(model: TranslatedPageModel, onClose: @escaping () -> Void) {
        self.init(model: model, onClose: onClose, extraButtons: { EmptyView() })
    }
}
