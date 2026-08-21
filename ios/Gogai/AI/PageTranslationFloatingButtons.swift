import SwiftUI

/// ページ内翻訳(TranslatedPageModel)の右下フローティングボタン群。
/// 上から: 混ぜ直し / 訳文の割合ステッパー(− 訳 40% +)/ engine 固有の追加ボタン(任意、再翻訳など)/ 閉じる。
/// システム翻訳(TranslatedPageView)・基盤モデル翻訳(FMTranslatedPageView)の両方が使う。
struct PageTranslationFloatingButtons<ExtraButtons: View>: View {
    @ObservedObject var model: TranslatedPageModel
    let onClose: () -> Void
    @ViewBuilder var extraButtons: () -> ExtraButtons

    /// 割合の操作は翻訳が完了し、訳が1件以上あるときだけ有効
    private var isMixEnabled: Bool {
        model.status == .done && model.hasTranslations
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            CircleIconButton(
                systemName: "shuffle",
                accessibilityLabel: "混ぜ直す",
                isEnabled: isMixEnabled && model.mixRatio > TranslationMix.minRatio && model.mixRatio < TranslationMix.maxRatio
            ) {
                Task { await model.reshuffle() }
            }
            mixRatioStepper
            extraButtons()
            CircleIconButton(systemName: "xmark", accessibilityLabel: "閉じる", action: onClose)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 70)
    }

    /// 訳文で表示する文の割合を 10% 刻みで増減するカプセル
    private var mixRatioStepper: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus", accessibilityLabel: "訳文を減らす", isEnabled: isMixEnabled && model.mixRatio > TranslationMix.minRatio) {
                Task { await changeRatio(by: -TranslationMix.step) }
            }
            Text("訳 \(model.mixRatio)%")
                .font(.footnote.monospacedDigit().weight(.medium))
                .frame(minWidth: 56)
                .accessibilityLabel("訳文の割合 \(model.mixRatio)パーセント")
            stepButton(systemName: "plus", accessibilityLabel: "訳文を増やす", isEnabled: isMixEnabled && model.mixRatio < TranslationMix.maxRatio) {
                Task { await changeRatio(by: TranslationMix.step) }
            }
        }
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .shadow(radius: 2, y: 1)
        .opacity(isMixEnabled ? 1 : 0.4)
    }

    private func stepButton(systemName: String, accessibilityLabel: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .frame(width: 40, height: 40)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
    }

    private func changeRatio(by delta: Int) async {
        let next = TranslationMix.clamp(model.mixRatio + delta)
        await model.setMixRatio(next)
        TranslationMix.savedRatio = next
    }
}

extension PageTranslationFloatingButtons where ExtraButtons == EmptyView {
    init(model: TranslatedPageModel, onClose: @escaping () -> Void) {
        self.init(model: model, onClose: onClose, extraButtons: { EmptyView() })
    }
}
