import XCTest
import WebKit
@testable import Gogai

@MainActor
final class TranslatedPageModelTests: XCTestCase {

    private func makeLoadedModel(html: String) async throws -> TranslatedPageModel {
        let model = TranslatedPageModel()
        model.loadHTML(html)
        for _ in 0..<200 {
            if model.status == .ready { return model }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("ページの読み込みが完了しなかった")
        throw URLError(.timedOut)
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
