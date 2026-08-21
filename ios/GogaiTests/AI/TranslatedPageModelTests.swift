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

    func test_extractTexts_svg内のテキストは対象外() async throws {
        // Why: SVG の text に span を挿入すると描画されなくなるため、最初から翻訳対象にしない
        let model = try await makeLoadedModel(html: """
        <html><body><svg><text>SvgLabel</text></svg><p>Visible</p></body></html>
        """)
        let texts = try await model.extractTexts()
        XCTAssertEqual(texts, ["Visible"])
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

    // MARK: - 文単位の分割と span 化

    func test_extractTexts_テキストノードを文単位に分割して返す() async throws {
        let model = try await makeLoadedModel(html: """
        <html><body><p id="p1">Hello world. Second one.</p><p id="p2">朝です。おはよう。</p></body></html>
        """)
        let texts = try await model.extractTexts()
        XCTAssertEqual(texts, ["Hello world.", "Second one.", "朝です。", "おはよう。"], "前後の空白は除かれる")
        let spanCount = try await model.webView.evaluateJavaScript("document.querySelectorAll('span.gogai-sent').length") as? Int
        XCTAssertEqual(spanCount, 4, "各文が span で包まれる")
        let p1Text = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(p1Text, "Hello world. Second one.", "span 化しても表示テキストは変わらない")
    }

    func test_applyTranslation_文ごとに訳文が入り文間の空白は保たれる() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello. World.</p></body></html>")
        let texts = try await model.extractTexts()
        XCTAssertEqual(texts, ["Hello.", "World."])

        await model.applyTranslation(at: 0, text: "こんにちは。")
        await model.applyTranslation(at: 1, text: "世界。")

        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "こんにちは。 世界。")
    }

    func test_extractTexts_再実行してもspanは二重にならず同じ文が得られる() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello. World.</p></body></html>")
        let first = try await model.extractTexts()
        await model.applyTranslation(at: 0, text: "こんにちは。")

        let second = try await model.extractTexts()

        XCTAssertEqual(first, second)
        XCTAssertFalse(model.hasTranslations, "再抽出で訳文はリセットされる")
        let spanCount = try await model.webView.evaluateJavaScript("document.querySelectorAll('span.gogai-sent').length") as? Int
        XCTAssertEqual(spanCount, 2)
        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "Hello. World.", "原文に戻っている")
    }

    // MARK: - ミックス割合(訳文で表示する文の割合)

    func test_mixRatio_0なら訳文を受け取っても原文のまま表示する() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello. World.</p></body></html>")
        _ = try await model.extractTexts()
        await model.setMixRatio(0)
        await model.applyTranslation(at: 0, text: "こんにちは。")
        await model.applyTranslation(at: 1, text: "世界。")

        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "Hello. World.")
        XCTAssertTrue(model.hasTranslations, "訳文自体は保持している")
        XCTAssertTrue(model.translatedIndices.isEmpty)
    }

    func test_setMixRatio_割合を上げると訳文表示の文が増える() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">One. Two. Three. Four.</p></body></html>")
        _ = try await model.extractTexts()
        for (i, t) in ["一。", "二。", "三。", "四。"].enumerated() {
            await model.applyTranslation(at: i, text: t)
        }

        await model.setMixRatio(50)
        XCTAssertEqual(model.mixRatio, 50)
        XCTAssertEqual(model.translatedIndices, [1, 3])
        var pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "One. 二。 Three. 四。")

        await model.setMixRatio(100)
        pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "一。 二。 三。 四。")
    }

    func test_reshuffle_同じ割合で別の文が訳文になる() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">One. Two. Three. Four.</p></body></html>")
        _ = try await model.extractTexts()
        for (i, t) in ["一。", "二。", "三。", "四。"].enumerated() {
            await model.applyTranslation(at: i, text: t)
        }
        await model.setMixRatio(50)

        await model.reshuffle()

        XCTAssertEqual(model.translatedIndices, [0, 2])
        let pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "一。 Two. 三。 Four.")
    }

    func test_文をタップすると原文と訳文が個別に切り替わる() async throws {
        let model = try await makeLoadedModel(html: "<html><body><p id=\"p1\">Hello. World.</p></body></html>")
        _ = try await model.extractTexts()
        await model.applyTranslation(at: 0, text: "こんにちは。")
        await model.applyTranslation(at: 1, text: "世界。")

        _ = try await model.webView.evaluateJavaScript("document.querySelector('[data-gogai-sent=\"0\"]').click(); true;")
        var pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "Hello. 世界。", "タップした文だけ原文に戻る")

        _ = try await model.webView.evaluateJavaScript("document.querySelector('[data-gogai-sent=\"0\"]').click(); true;")
        pText = try await model.webView.evaluateJavaScript("document.getElementById('p1').textContent") as? String
        XCTAssertEqual(pText, "こんにちは。 世界。", "もう一度タップで訳文に戻る")
    }

    func test_初期化時の割合は範囲内にクランプされる() {
        XCTAssertEqual(TranslatedPageModel(mixRatio: 140).mixRatio, 100)
        XCTAssertEqual(TranslatedPageModel(mixRatio: -5).mixRatio, 0)
        XCTAssertEqual(TranslatedPageModel().mixRatio, 100, "既定は全文訳文(従来の挙動)")
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
