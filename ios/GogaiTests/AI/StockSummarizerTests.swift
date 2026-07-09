import XCTest
@testable import Gogai

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
        } catch let error as LocalAIError {
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

    // MARK: - 不完全な出力のセクション個別生成フォールバック
    // (オンデバイスモデルが1回の生成では一部セクションしか埋めないことがあるため)

    func test_summarize_1回で完全な出力ならセクション個別生成にフォールバックしない() async throws {
        let generator = MockTextGenerator()
        generator.responses = [
            "## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD",
        ]
        let summarizer = StockSummarizer(generator: generator)

        _ = try await summarizer.summarize(title: "タイトル", text: "本文")

        XCTAssertEqual(generator.callCount, 1, "1回で parse できるならフォールバックしない")
    }

    func test_summarize_一部セクションが空ならセクションを個別生成して固定見出しで組み立てる() async throws {
        // 1回目(combined)は要約以外が空 → parse 失敗 → セクション個別生成へフォールバック
        let generator = MockTextGenerator()
        generator.responses = [
            "## 何についての記事か\n## 何の目的で書かれたか\n## 筆者が一番伝えたいこと\n## 要約(20行以内)\nD",
            "トピック本文", "目的本文", "主張本文", "要約1\n要約2",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "本文")

        XCTAssertEqual(generator.callCount, 5, "combined 1回 + 4セクション個別生成")
        let parsed = StockSummary.parse(result)
        XCTAssertEqual(parsed?.topic, "トピック本文")
        XCTAssertEqual(parsed?.purpose, "目的本文")
        XCTAssertEqual(parsed?.mainMessage, "主張本文")
        XCTAssertEqual(parsed?.summaryLines, ["要約1", "要約2"])
    }

    func test_summarize_フォールバック時に空で返ったセクションだけ再生成する() async throws {
        let generator = MockTextGenerator()
        generator.responses = [
            "壊れた出力",       // combined: parse 失敗
            "", "トピック本文",  // topic: 1回目空 → 再生成
            "目的本文", "主張本文", "要約",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "本文")

        XCTAssertEqual(StockSummary.parse(result)?.topic, "トピック本文")
    }

    func test_summarize_フォールバックしても空なら固定見出しは必ず組み立てられる() async throws {
        // モデルが常に空を返しても、見出し(青表示の元)は必ず揃い parse は成功する
        let generator = MockTextGenerator()
        generator.responses = []
        generator.result = "" // 常に空
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "本文")

        XCTAssertNotNil(StockSummary.parse(result), "空でも4見出しが揃い parse できること(=見出しは常に青)")
    }

    func test_summarize_フォールバック時にセクション本文へ紛れた見出し行を除去する() async throws {
        let generator = MockTextGenerator()
        generator.responses = [
            "壊れた出力",
            "## 何についての記事か\n実際のトピック", "目的本文", "主張本文", "要約",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "本文")

        XCTAssertEqual(StockSummary.parse(result)?.topic, "実際のトピック", "本文に紛れた見出し行は除去する")
    }

    func test_summarize_フォールバック時に要約は20行以内へ切り詰める() async throws {
        let bodyLines = (1...30).map { "行\($0)" }.joined(separator: "\n")
        let generator = MockTextGenerator()
        generator.responses = [
            "壊れた出力",
            "トピック本文", "目的本文", "主張本文", bodyLines,
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "本文")

        XCTAssertLessThanOrEqual(StockSummary.parse(result)?.summaryLines.count ?? 0, 20)
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
