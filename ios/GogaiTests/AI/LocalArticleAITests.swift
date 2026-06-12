import XCTest
@testable import Gogai

/// TextGenerating のモック: 受け取った instructions / prompt を記録して固定文字列を返す
private final class MockTextGenerator: TextGenerating, @unchecked Sendable {
    var lastInstructions: String?
    var lastPrompt: String?
    var result: String = "生成結果"
    var error: Error?

    func generate(instructions: String, prompt: String) async throws -> String {
        lastInstructions = instructions
        lastPrompt = prompt
        if let error { throw error }
        return result
    }
}

final class LocalArticleAITests: XCTestCase {

    // MARK: - summarize

    func test_summarize_日本語要約のinstructionsで本文を渡す() async throws {
        let generator = MockTextGenerator()
        generator.result = "これは要約です。"
        let ai = LocalArticleAI(generator: generator)

        let result = try await ai.summarize(title: "Big News", content: "<p>Hello <b>World</b></p>")

        XCTAssertEqual(result, "これは要約です。")
        XCTAssertTrue(generator.lastInstructions?.contains("要約") == true)
        XCTAssertTrue(generator.lastInstructions?.contains("日本語") == true)
        XCTAssertTrue(generator.lastPrompt?.contains("Big News") == true)
        XCTAssertTrue(generator.lastPrompt?.contains("Hello World") == true, "HTML タグは除去して渡す")
        XCTAssertFalse(generator.lastPrompt?.contains("<p>") == true)
    }

    func test_summarize_本文がなければsummaryやタイトルでも動く() async throws {
        let generator = MockTextGenerator()
        let ai = LocalArticleAI(generator: generator)

        _ = try await ai.summarize(title: "Title Only", content: nil)
        XCTAssertTrue(generator.lastPrompt?.contains("Title Only") == true)
    }

    func test_summarize_タイトルも本文も空ならemptyContentを投げる() async {
        let ai = LocalArticleAI(generator: MockTextGenerator())
        do {
            _ = try await ai.summarize(title: nil, content: "   ")
            XCTFail("emptyContent エラーになるべき")
        } catch let error as LocalArticleAIError {
            XCTAssertEqual(error, .emptyContent)
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }

    // MARK: - translateToJapanese

    func test_translateToJapanese_翻訳instructionsで本文を渡す() async throws {
        let generator = MockTextGenerator()
        generator.result = "これは翻訳です。"
        let ai = LocalArticleAI(generator: generator)

        let result = try await ai.translateToJapanese(title: "Hello", content: "This is a pen.")

        XCTAssertEqual(result, "これは翻訳です。")
        XCTAssertTrue(generator.lastInstructions?.contains("翻訳") == true)
        XCTAssertTrue(generator.lastInstructions?.contains("日本語") == true)
        XCTAssertTrue(generator.lastPrompt?.contains("This is a pen.") == true)
    }

    // MARK: - preparePrompt（HTML 除去と切り詰め）

    func test_preparePrompt_HTMLタグとエンティティを除去する() {
        let text = LocalArticleAI.preparePrompt(
            title: nil,
            content: "<div><h1>Title</h1><p>Body &amp; more&nbsp;text</p></div>"
        )
        XCTAssertFalse(text.contains("<"))
        XCTAssertTrue(text.contains("Body & more text"))
    }

    func test_preparePrompt_オンデバイスモデルのコンテキスト上限に収まるよう切り詰める() {
        let longContent = String(repeating: "あ", count: 10_000)
        let text = LocalArticleAI.preparePrompt(title: "T", content: longContent)
        XCTAssertLessThanOrEqual(text.count, LocalArticleAI.maxPromptLength)
    }

    func test_preparePrompt_タイトルと本文を結合する() {
        let text = LocalArticleAI.preparePrompt(title: "見出し", content: "本文")
        XCTAssertTrue(text.contains("見出し"))
        XCTAssertTrue(text.contains("本文"))
    }

    // MARK: - LocalAI.isAvailable（OS ゲート）

    func test_isAvailable_iOS27未満ではfalse() {
        // このテストスイートは iOS 26 シミュレーターで動くため、
        // iOS 27 ゲートにより必ず false になることを固定する
        if #unavailable(iOS 27.0) {
            XCTAssertFalse(LocalAI.isAvailable)
            XCTAssertNil(LocalAI.makeArticleAI())
        }
    }
}
