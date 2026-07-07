import XCTest
import WebKit
import Combine
@testable import Gogai

private enum PageLoadWaitError: Error {
    case timedOut
    case failed(String)
}

@MainActor
final class TranslatedPageModelTests: XCTestCase {

    /// 一度だけ resume することを保証するための箱(sink とタイムアウト Task の二重 resume を防ぐ)
    @MainActor
    private final class ResumeGuard {
        private var resumed = false
        func resumeOnce(_ body: () -> Void) {
            guard !resumed else { return }
            resumed = true
            body()
        }
    }

    /// ポーリングではなく status の変化を直接購読して待つ(didFinish 発火と同時に resume する)。
    /// タイムアウトはポーリング時代の 5 秒より余裕を持たせて 10 秒にする。
    private func makeLoadedModel(html: String) async throws -> TranslatedPageModel {
        let model = TranslatedPageModel()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guard_ = ResumeGuard()
            var cancellable: AnyCancellable?
            cancellable = model.$status.sink { status in
                switch status {
                case .ready:
                    guard_.resumeOnce {
                        cancellable?.cancel()
                        continuation.resume()
                    }
                case .failed(let message):
                    guard_.resumeOnce {
                        cancellable?.cancel()
                        continuation.resume(throwing: PageLoadWaitError.failed(message))
                    }
                case .loading, .translating, .done:
                    break
                }
            }
            model.loadHTML(html)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                guard_.resumeOnce {
                    cancellable?.cancel()
                    continuation.resume(throwing: PageLoadWaitError.timedOut)
                }
            }
        }
        return model
    }

    // MARK: - extractTexts

    func test_extractTexts_本文のテキストノードを抽出する() async throws {
        let model = try await makeLoadedModel(html: """
        <html><body><h1>Hello</h1><p>World <b>bold</b></p><img src="x.png"></body></html>
        """)
        let texts = try await model.extractTexts()
        XCTAssertTrue(texts.contains { $0.contains("Hello") })
        XCTAssertTrue(texts.contains { $0.contains("World") })
        XCTAssertTrue(texts.contains { $0.contains("bold") })
    }

    func test_extractTexts_scriptやstyleやcodeの中身は対象外() async throws {
        let model = try await makeLoadedModel(html: """
        <html><body><script>var s = "jscode";</script><style>.a{color:red}</style>
        <code>let x = 1</code><p>Visible</p></body></html>
        """)
        let texts = try await model.extractTexts()
        XCTAssertTrue(texts.contains { $0.contains("Visible") })
        XCTAssertFalse(texts.contains { $0.contains("jscode") })
        XCTAssertFalse(texts.contains { $0.contains("color:red") })
        XCTAssertFalse(texts.contains { $0.contains("let x = 1") }, "code ブロックは翻訳しない")
    }

    // MARK: - applyTranslation（レイアウト保持の書き戻し）

    func test_applyTranslation_テキストだけ差し替わり画像とタグは残る() async throws {
        let model = try await makeLoadedModel(html: """
        <html><body><p id="p1">Hello</p><img id="img1" src="x.png"></body></html>
        """)
        let texts = try await model.extractTexts()
        let index = try XCTUnwrap(texts.firstIndex { $0.contains("Hello") })

        await model.applyTranslation(at: index, text: "こんにちは")

        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "こんにちは")
        let imgExists = try await model.webView.evaluateJavaScript("document.getElementById('img1') !== null ? 1 : 0") as? Int
        XCTAssertEqual(imgExists, 1, "画像はそのまま残る")
        let pTag = try await model.webView.evaluateJavaScript("document.getElementById('p1').tagName") as? String
        XCTAssertEqual(pTag, "P", "タグ構造は変わらない")
    }

    // MARK: - 原文 ⇄ 訳文のトグル

    func test_showOriginal_翻訳後に原文へ戻せる() async throws {
        let model = try await makeLoadedModel(html: """
        <html><body><p id="p1">Hello</p><p id="p2">World</p></body></html>
        """)
        let texts = try await model.extractTexts()
        let helloIndex = try XCTUnwrap(texts.firstIndex { $0.contains("Hello") })
        await model.applyTranslation(at: helloIndex, text: "こんにちは")
        XCTAssertFalse(model.isShowingOriginal)

        await model.showOriginal()

        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "Hello", "原文に戻る")
        XCTAssertTrue(model.isShowingOriginal)
    }

    func test_showTranslation_原文表示から訳文へ戻せる() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello</p></body></html>")
        let texts = try await model.extractTexts()
        let index = try XCTUnwrap(texts.firstIndex { $0.contains("Hello") })
        await model.applyTranslation(at: index, text: "こんにちは")

        await model.showOriginal()
        await model.showTranslation()

        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "こんにちは", "訳文表示に戻る")
        XCTAssertFalse(model.isShowingOriginal)
    }

    // MARK: - restoreTranslations（サーバー保存済み訳文の復元）

    func test_restoreTranslations_保存済みの訳文を一括で書き戻す() async throws {
        let model = try await makeLoadedModel(html: """
        <html><body><p id="p1">Hello</p><p id="p2">World</p></body></html>
        """)
        _ = try await model.extractTexts()

        await model.restoreTranslations([0: "こんにちは", 1: "世界"])

        let p1Text = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        let p2Text = try await model.webView.evaluateJavaScript("document.getElementById('p2').textContent") as? String
        XCTAssertEqual(p1Text, "こんにちは")
        XCTAssertEqual(p2Text, "世界")
        XCTAssertTrue(model.hasTranslations)
    }

    func test_restoreTranslations_空辞書なら何もしない() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello</p></body></html>")
        _ = try await model.extractTexts()

        await model.restoreTranslations([:])

        XCTAssertFalse(model.hasTranslations)
    }

    func test_hasTranslations_訳を適用するまでfalse() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p>Hello</p></body></html>")
        _ = try await model.extractTexts()
        XCTAssertFalse(model.hasTranslations)
        await model.applyTranslation(at: 0, text: "こんにちは")
        XCTAssertTrue(model.hasTranslations)
    }

    func test_applyTranslation_引用符や改行を含む訳文も安全に書き戻せる() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello</p></body></html>")
        let texts = try await model.extractTexts()
        let index = try XCTUnwrap(texts.firstIndex { $0.contains("Hello") })

        let tricky = "「引用」と \"quote\" と \\backslash\\ と\n改行"
        await model.applyTranslation(at: index, text: tricky)

        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, tricky)
    }
}

final class TranslationDestinationTests: XCTestCase {
    func test_システム翻訳かつリンクありならページ内翻訳() {
        let dest = TranslationDestination.forCurrentSettings(
            engine: .translationFramework, link: "https://example.com/a")
        XCTAssertEqual(dest, .translatedPage(URL(string: "https://example.com/a")!))
    }

    func test_基盤モデル選択時はテキスト表示() {
        let dest = TranslationDestination.forCurrentSettings(
            engine: .foundationModel, link: "https://example.com/a")
        XCTAssertEqual(dest, .textSheet)
    }

    func test_リンクがなければテキスト表示にフォールバック() {
        let dest = TranslationDestination.forCurrentSettings(
            engine: .translationFramework, link: nil)
        XCTAssertEqual(dest, .textSheet)
    }
}
