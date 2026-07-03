import XCTest
@testable import Gogai

private final class MockTextGenerator: TextGenerating, @unchecked Sendable {
    var responses: [String] = []
    var receivedPrompts: [String] = []
    var receivedInstructions: [String] = []
    var error: Error?

    func generate(instructions: String, prompt: String) async throws -> String {
        receivedInstructions.append(instructions)
        receivedPrompts.append(prompt)
        if let error { throw error }
        guard !responses.isEmpty else { return "生成結果" }
        return responses.removeFirst()
    }
}

final class StockSummarizerTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - summarize(title:text:) 短文(1段)

    func test_summarize_短い本文は1回のプロンプトで最終形式を生成する() async throws {
        let generator = MockTextGenerator()
        generator.responses = ["## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "短い本文です。")

        XCTAssertEqual(generator.receivedPrompts.count, 1, "短文は中間要約を挟まず1回で生成する")
        XCTAssertTrue(generator.receivedPrompts[0].contains("タイトル"))
        XCTAssertTrue(generator.receivedPrompts[0].contains("短い本文です。"))
        XCTAssertTrue(generator.receivedInstructions[0].contains("日本語"))
        XCTAssertTrue(result.contains("## 何についての記事か"))
    }

    func test_summarize_タイトルも本文も空ならemptyContentを投げる() async {
        let summarizer = StockSummarizer(generator: MockTextGenerator())
        do {
            _ = try await summarizer.summarize(title: nil, text: "   ")
            XCTFail("emptyContent になるべき")
        } catch let error as StockSummarizerError {
            XCTAssertEqual(error, .emptyContent)
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }

    // MARK: - 長文は map-reduce で中間要約を経由する

    func test_summarize_長い本文はチャンクごとに中間要約してから最終生成する() async throws {
        let generator = MockTextGenerator()
        let longText = String(repeating: "あ", count: StockSummarizer.chunkSize * 3)
        generator.responses = [
            "中間要約1", "中間要約2", "中間要約3",
            "## 何についての記事か\nX\n## 何の目的で書かれたか\nY\n## 筆者が一番伝えたいこと\nZ\n## 要約(20行以内)\nW",
        ]
        let summarizer = StockSummarizer(generator: generator)

        _ = try await summarizer.summarize(title: "T", text: longText)

        // 3チャンクの中間要約 + 最終生成の計4回
        XCTAssertEqual(generator.receivedPrompts.count, 4)
        XCTAssertTrue(generator.receivedInstructions[0].contains("箇条書き"))
        // 最終プロンプトには中間要約の結果が含まれる
        XCTAssertTrue(generator.receivedPrompts[3].contains("中間要約1"))
    }

    func test_summarize_チャンク数はmaxChunksで打ち切る() {
        let text = String(repeating: "a", count: StockSummarizer.chunkSize * (StockSummarizer.maxChunks + 5))
        let chunks = StockSummarizer.chunk(text, size: StockSummarizer.chunkSize, maxChunks: StockSummarizer.maxChunks)
        XCTAssertEqual(chunks.count, StockSummarizer.maxChunks)
    }

    // MARK: - 20行切り詰め

    func test_enforceSummaryLineLimit_20行を超える要約セクションを切り詰める() {
        let bodyLines = (1...30).map { "行\($0)" }.joined(separator: "\n")
        let text = "## 何についての記事か\nA\n## 要約(20行以内)\n\(bodyLines)"

        let limited = StockSummarizer.enforceSummaryLineLimit(text, limit: 20)

        let summarySection = limited.components(separatedBy: "## 要約(20行以内)\n")[1]
        let lineCount = summarySection.components(separatedBy: "\n").count
        XCTAssertLessThanOrEqual(lineCount, 20)
        XCTAssertTrue(limited.contains("## 何についての記事か"), "他のセクションは維持される")
    }

    func test_enforceSummaryLineLimit_要約見出しがなければそのまま返す() {
        let text = "見出しなしの本文"
        XCTAssertEqual(StockSummarizer.enforceSummaryLineLimit(text), text)
    }

    // MARK: - summarize(url:title:) URL からのフェッチ

    func test_summarizeFromURL_ページ本文を取得してから要約する() async throws {
        MockURLProtocol.requestHandler = { _ in
            (200, Data("<html><body><p>Fetched body text</p></body></html>".utf8))
        }
        let generator = MockTextGenerator()
        generator.responses = ["## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"]
        let summarizer = StockSummarizer(generator: generator)

        _ = try await summarizer.summarize(url: URL(string: "https://example.com/a")!, title: "T", session: .mock())

        XCTAssertTrue(generator.receivedPrompts[0].contains("Fetched body text"))
    }
}
