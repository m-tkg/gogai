import SwiftUI

/// ページ内翻訳(TranslatedPageModel)の読み込み・翻訳進捗を表示するステータスバー。
/// システム翻訳(TranslatedPageView)・基盤モデル翻訳(FMTranslatedPageView)の両方が使う。
struct PageTranslationStatusBar: View {
    let status: TranslatedPageModel.Status
    let translatedCount: Int
    let totalCount: Int

    var body: some View {
        switch status {
        case .loading:
            statusLabel("ページを読み込んでいます…", showsProgress: true)
        case .ready, .translating:
            statusLabel(
                totalCount > 0
                    ? "翻訳中… (\(translatedCount)/\(totalCount))"
                    : "翻訳の準備中…",
                showsProgress: true
            )
        case .failed(let message):
            statusLabel("翻訳に失敗しました: \(message)", showsProgress: false)
        case .done:
            EmptyView()
        }
    }

    private func statusLabel(_ text: String, showsProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView() }
            Text(text).font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 12)
    }
}
