import SwiftUI

/// 画面右下にフローティング配置する円形アイコンボタン。
/// 記事ページの AI ボタン・閉じるボタン、翻訳ページのトグル・閉じるボタンで共通利用する。
struct CircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.quaternary))
                .shadow(radius: 2, y: 1)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
    }
}
