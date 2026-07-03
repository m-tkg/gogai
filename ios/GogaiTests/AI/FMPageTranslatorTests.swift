import XCTest
@testable import Gogai

private final class MockTextGenerator: TextGenerating, @unchecked Sendable {
    /// 呼び出しごとに順番に返す応答(プロンプトから id を機械的に再構成したい場合は nil のままにして generate 内で組み立てる)
    var responseHandler: ((String, String) -> String)?
    var receivedPrompts: [String] = []
    var receivedInstructions: [String] = []
    var error: Error?

    func generate(instructions: String, prompt: String) async throws -> String {
        receivedInstructions.append(instructions)
        receivedPrompts.append(prompt)
        if let error { throw error }
        return responseHandler?(instructions, prompt) ?? ""
    }
}

/// プロンプト中の「⟦id⟧原文」をそのまま「⟦id⟧訳:原文」の形に変換して返す(⟦ctx⟧行は無視する)
private func echoTranslate(_ prompt: String) -> String {
    prompt
        .components(separatedBy: "\n")
        .compactMap { line -> String? in
            guard let match = try? NSRegularExpression(pattern: "^⟦(\\d+)⟧(.*)$").firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)
            ), let idRange = Range(match.range(at: 1), in: line), let textRange = Range(match.range(at: 2), in: line) else {
                return nil
            }
            return "⟦\(line[idRange])⟧訳:\(line[textRange])"
        }
        .joined(separator: "\n")
}

final class FMPageTranslatorTests: XCTestCase {

    // MARK: - parseResponse

    func test_parseResponse_id付き行を辞書にパースする() {
        let response = "⟦0⟧こんにちは\n⟦2⟧世界"
        let result = FMPageTranslator.parseResponse(response)
        XCTAssertEqual(result, [0: "こんにちは", 2: "世界"])
    }

    func test_parseResponse_ctx行は無視される() {
        let response = "⟦ctx⟧参考文\n⟦1⟧本文の訳"
        let result = FMPageTranslator.parseResponse(response)
        XCTAssertEqual(result, [1: "本文の訳"])
    }

    func test_parseResponse_複数行にまたがる訳文も1つの値として扱う() {
        let response = "⟦0⟧1行目\n2行目\n⟦1⟧次のノード"
        let result = FMPageTranslator.parseResponse(response)
        XCTAssertEqual(result[0], "1行目\n2行目")
        XCTAssertEqual(result[1], "次のノード")
    }

    // MARK: - makeBatches

    func test_makeBatches_文字数上限でバッチを分割する() {
        let segments = (0..<5).map { FMPageTranslator.Segment(index: $0, text: String(repeating: "a", count: 500)) }
        let batches = FMPageTranslator.makeBatches(segments, charBudget: 1000)
        // 500文字 x 5 を上限1000文字で分割 → 2件ずつ + 端数1件
        XCTAssertEqual(batches.map { $0.count }, [2, 2, 1])
    }

    func test_makeBatches_単体で上限を超えるセグメントも1バッチに収める() {
        let segments = [FMPageTranslator.Segment(index: 0, text: String(repeating: "a", count: 5000))]
        let batches = FMPageTranslator.makeBatches(segments, charBudget: 1000)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].count, 1)
    }

    // MARK: - translate(texts:indicesToTranslate:pageTitle:)

    func test_translate_バッチ単位で翻訳しindexごとの訳文を返す() async {
        let generator = MockTextGenerator()
        generator.responseHandler = { _, prompt in echoTranslate(prompt) }
        let translator = FMPageTranslator(generator: generator)

        let texts = ["Hello", "World"]
        let result = await translator.translate(texts: texts, indicesToTranslate: [0, 1], pageTitle: "Test Page")

        XCTAssertEqual(result[0], "訳:Hello")
        XCTAssertEqual(result[1], "訳:World")
        XCTAssertTrue(generator.receivedInstructions[0].contains("Test Page"))
    }

    func test_translate_直前ノードを文脈として渡す() async {
        let generator = MockTextGenerator()
        generator.responseHandler = { _, prompt in echoTranslate(prompt) }
        let translator = FMPageTranslator(generator: generator)

        // 1つ目のバッチが収まりきらないよう文字数を大きくして、2バッチ目の文脈確認をしやすくする
        let texts = ["Context node", "Target node"]
        _ = await translator.translate(texts: texts, indicesToTranslate: [1], pageTitle: "T")

        XCTAssertTrue(generator.receivedPrompts[0].contains("⟦ctx⟧Context node"), "翻訳対象の直前ノードが文脈として渡される")
        XCTAssertFalse(generator.receivedPrompts[0].contains("⟦0⟧"), "文脈行は⟦id⟧形式で出力対象にしない")
    }

    func test_translate_応答にid欠落があれば該当ノードのみ個別リトライする() async {
        let generator = MockTextGenerator()
        var callCount = 0
        generator.responseHandler = { _, prompt in
            callCount += 1
            if callCount == 1 {
                // 最初のバッチ応答では id=1 が欠落
                return "⟦0⟧訳0"
            }
            return echoTranslate(prompt)
        }
        let translator = FMPageTranslator(generator: generator)

        let result = await translator.translate(texts: ["A", "B"], indicesToTranslate: [0, 1], pageTitle: "T")

        XCTAssertEqual(result[0], "訳0")
        XCTAssertEqual(result[1], "訳:B", "欠落した id は個別プロンプトでリトライされる")
        XCTAssertEqual(callCount, 2, "バッチ1回 + 個別リトライ1回")
    }

    func test_translate_個別リトライも失敗すれば結果に含まれない() async {
        let generator = MockTextGenerator()
        generator.responseHandler = { _, _ in "応答フォーマットが不正" }
        let translator = FMPageTranslator(generator: generator)

        let result = await translator.translate(texts: ["A"], indicesToTranslate: [0], pageTitle: "T")

        XCTAssertNil(result[0], "パースできない応答のノードは結果に含まれない(呼び出し側が原文のまま表示する)")
    }

    func test_translate_空配列なら何もしない() async {
        let generator = MockTextGenerator()
        let translator = FMPageTranslator(generator: generator)

        let result = await translator.translate(texts: [], indicesToTranslate: [], pageTitle: "T")

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(generator.receivedPrompts.isEmpty)
    }
}
