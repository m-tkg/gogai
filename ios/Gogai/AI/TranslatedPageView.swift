import SwiftUI
import WebKit
import Translation

/// 翻訳ボタンの遷移先（設定とリンク有無で決まる）
enum TranslationDestination: Equatable {
    /// 訳文テキストを sheet 表示（設定画面で選んだ AI、またはリンクなしのフォールバック）
    case textSheet
    /// レイアウト保持のページ内翻訳（システム翻訳 + リンクあり）
    case translatedPage(URL)

    static func forCurrentSettings(engine: TranslationEngine, link: String?) -> TranslationDestination {
        guard engine == .translationFramework, let link, let url = URL(string: link) else {
            return .textSheet
        }
        return .translatedPage(url)
    }
}

/// レイアウトを保ったまま、ページ内の文字だけを日本語に翻訳して表示するビュー。
/// SFSafariViewController はページ操作不可のため、翻訳時のみ WKWebView を使う
/// （Safari 拡張・広告ブロックは効かない）。
@available(iOS 18.0, macCatalyst 26.0, *)
struct TranslatedPageView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = TranslatedPageModel(mixRatio: TranslationMix.savedRatio)
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        PageTranslationWebView(model: model)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                PageTranslationStatusBar(status: model.status, translatedCount: model.translatedCount, totalCount: model.totalCount)
            }
            // 記事ページ（翻訳前）と同じ右下フローティング配置でボタンを並べる
            .overlay(alignment: .bottomTrailing) {
                PageTranslationFloatingButtons(model: model) { dismiss() }
            }
            .translationTask(configuration) { session in
            // Why: TranslationSession は non-Sendable のため unsafe 束縛で
            // region isolation を回避する（このクロージャ内で逐次アクセスのみ）
            nonisolated(unsafe) let session = session
            await translatePage(using: session)
        }
        .onAppear { model.load(url) }
        .onChange(of: model.status) { _, newStatus in
            // ページ読み込み完了後に翻訳セッションを起動する
            if newStatus == .ready {
                configuration = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: "ja")
                )
            }
        }
    }

    @available(iOS 18.0, macCatalyst 26.0, *)
    private func translatePage(using session: TranslationSession) async {
        // 翻訳中にバックグラウンドへ移っても継続する（システム猶予内）
        await BackgroundExecution.run(name: "LocalAI.translatePage") {
            await runTranslation(using: session)
        }
    }

    @available(iOS 18.0, macCatalyst 26.0, *)
    private func runTranslation(using session: TranslationSession) async {
        do {
            let texts = try await model.extractTexts()
            guard !texts.isEmpty else {
                model.markDone()
                return
            }
            model.beginTranslating(total: texts.count)

            // キャッシュ済みの文は即座に書き戻し、未訳のものだけ翻訳セッションへ。
            // clientIdentifier に文 index を載せ、訳が届き次第その場で書き戻す
            let cache = TranslationCache.shared
            var batch: [TranslationSession.Request] = []
            for (index, text) in texts.enumerated() {
                if let cached = cache.target(for: text, engine: .translationFramework) {
                    await model.applyTranslation(at: index, text: cached)
                } else {
                    batch.append(TranslationSession.Request(sourceText: text, clientIdentifier: String(index)))
                }
            }

            if !batch.isEmpty {
                for try await response in session.translate(batch: batch) {
                    if let id = response.clientIdentifier, let index = Int(id) {
                        await model.applyTranslation(at: index, text: response.targetText)
                        cache.store(source: texts[index], target: response.targetText, engine: .translationFramework)
                    }
                }
                cache.persist()
            }
            model.markDone()
        } catch {
            model.markFailed(error.localizedDescription)
        }
    }
}
