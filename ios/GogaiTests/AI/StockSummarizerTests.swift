import XCTest
@testable import Gogai

final class StockSummarizerTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private var aiInputText: String {
        String(repeating: "本文", count: 51)
    }

    /// 5セクションすべて揃った完全なモック応答
    private var completeResponse: String {
        "## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD\n## この記事から得られる学び\nE"
    }

    // MARK: - summarize(title:text:) 短文(1段)

    func test_summarize_100文字以下の本文はAIを呼ばずそのまま要約欄に表示する() async throws {
        let generator = MockTextGenerator()
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: "短い本文です。")

        XCTAssertEqual(generator.callCount, 0)
        let summary = try XCTUnwrap(StockSummary.parse(result))
        XCTAssertEqual(summary.summaryLines, [
            "内容が少ないため、要約せず本文をそのまま表示します。",
            "短い本文です。",
        ])
        XCTAssertEqual(summary.learningLines, [StockSummarizer.sectionPlaceholder], "学びを捏造せずプレースホルダで埋める")
    }

    func test_summarize_101文字以上の本文は1回のプロンプトで最終形式を生成する() async throws {
        let generator = MockTextGenerator()
        generator.responses = [completeResponse]
        let summarizer = StockSummarizer(generator: generator)
        let text = String(repeating: "あ", count: StockSummarizer.noSummaryNeededTextLimit + 1)

        let result = try await summarizer.summarize(title: "タイトル", text: text)

        XCTAssertEqual(generator.receivedPrompts.count, 1, "101文字以上は中間要約を挟まず1回で生成する")
        XCTAssertTrue(generator.receivedPrompts[0].contains("タイトル"))
        XCTAssertTrue(generator.receivedPrompts[0].contains(text))
        XCTAssertTrue(generator.receivedInstructions[0].contains("日本語"))
        XCTAssertTrue(result.contains("## 何についての記事か"))
    }

    @MainActor
    func test_summarize_進捗ログに整形とAIリクエストと解析結果を出す() async throws {
        let generator = MockTextGenerator()
        generator.responses = [completeResponse]
        var logs: [String] = []
        let summarizer = StockSummarizer(generator: generator, providerLabel: "Gemini") { message in
            logs.append(message)
        }

        _ = try await summarizer.summarize(title: "タイトル", text: String(repeating: "あ", count: StockSummarizer.noSummaryNeededTextLimit + 1))

        XCTAssertTrue(logs.contains("本文を要約用に整形中"))
        XCTAssertTrue(logs.contains { $0.contains("Geminiへ要約リクエスト送信中") })
        XCTAssertTrue(logs.contains("要約レスポンスの解析に成功"))
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
            completeResponse,
        ]
        let summarizer = StockSummarizer(generator: generator)

        _ = try await summarizer.summarize(title: "T", text: longText)

        // 3チャンクの中間要約 + 最終生成の計4回
        XCTAssertEqual(generator.receivedPrompts.count, 4)
        XCTAssertTrue(generator.receivedInstructions[0].contains("箇条書き"))
        // 最終プロンプトには中間要約の結果が含まれる
        XCTAssertTrue(generator.receivedPrompts[3].contains("中間要約1"))
    }

    func test_summarize_外部AIでは長い本文でも1回のリクエストに抑える() async throws {
        let generator = RemoteAITextGenerator(provider: .gemini, apiKey: "key", session: .mock())
        let longText = String(repeating: "あ", count: StockSummarizer.chunkSize * 3)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/interactions")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertLessThanOrEqual((json["input"] as? String)?.count ?? 0, StockSummarizer.remoteMaxPromptLength + 100)
            return (200, Data(###"{"output_text":"## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"}"###.utf8))
        }
        let summarizer = StockSummarizer(generator: generator)

        _ = try await summarizer.summarize(title: "T", text: longText)
    }

    func test_summarize_外部AIの形式崩れでは追加リクエストせず見出しを補う() async throws {
        var requestCount = 0
        let generator = RemoteAITextGenerator(provider: .gemini, apiKey: "key", session: .mock())
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (200, Data(#"{"output_text":"形式が崩れた要約"}"#.utf8))
        }
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "T", text: aiInputText)

        XCTAssertEqual(requestCount, 1)
        let parsed = try XCTUnwrap(StockSummary.parse(result))
        XCTAssertTrue(result.contains("形式が崩れた要約"))
        XCTAssertEqual(parsed.learningLines, [StockSummarizer.sectionPlaceholder], "外部AIでは学びも追加リクエストせずプレースホルダ")
    }

    func test_summarize_外部AIは学びが欠けても追加リクエストしない() async throws {
        var requestCount = 0
        let generator = RemoteAITextGenerator(provider: .gemini, apiKey: "key", session: .mock())
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (200, Data(###"{"output_text":"## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"}"###.utf8))
        }
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "T", text: aiInputText)

        XCTAssertEqual(requestCount, 1, "rate limit 回避のため学びの追加生成は行わない")
        XCTAssertNil(StockSummary.parse(result)?.learningLines)
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

    func test_enforceSummaryLineLimit_要約の後の学びセクションは切り詰めで消えない() {
        let bodyLines = (1...30).map { "行\($0)" }.joined(separator: "\n")
        let text = "## 要約(20行以内)\n\(bodyLines)\n## この記事から得られる学び\n学び1"

        let limited = StockSummarizer.enforceSummaryLineLimit(text, limit: 20)

        XCTAssertTrue(limited.contains("## この記事から得られる学び"), "学びの見出しは保持される")
        XCTAssertTrue(limited.contains("学び1"), "学びの本文は保持される")
        XCTAssertFalse(limited.contains("行21"), "要約本文は20行に切り詰められる")
    }

    // MARK: - 不完全な出力のセクション個別生成フォールバック
    // (オンデバイスモデルが1回の生成では一部セクションしか埋めないことがあるため)

    func test_summarize_1回で完全な出力ならセクション個別生成にフォールバックしない() async throws {
        let generator = MockTextGenerator()
        generator.responses = [completeResponse]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertEqual(generator.callCount, 1, "1回で parse できるならフォールバックしない")
        XCTAssertEqual(StockSummary.parse(result)?.learningLines, ["E"])
    }

    func test_summarize_オンデバイスで学びだけ欠けたら学びのみ追加生成する() async throws {
        let generator = MockTextGenerator()
        generator.responses = [
            "## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD",
            "学び本文",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertEqual(generator.callCount, 2, "combined 1回 + 学びの追加生成1回")
        let parsed = StockSummary.parse(result)
        XCTAssertEqual(parsed?.topic, "A", "既存セクションは1回目の値を維持する")
        XCTAssertEqual(parsed?.summaryLines, ["D"])
        XCTAssertEqual(parsed?.learningLines, ["学び本文"])
    }

    func test_summarize_一部セクションが空ならセクションを個別生成して固定見出しで組み立てる() async throws {
        // 1回目(combined)は要約以外が空 → parse 失敗 → セクション個別生成へフォールバック
        let generator = MockTextGenerator()
        generator.responses = [
            "## 何についての記事か\n## 何の目的で書かれたか\n## 筆者が一番伝えたいこと\n## 要約(20行以内)\nD",
            "トピック本文", "目的本文", "主張本文", "要約1\n要約2", "学び本文",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertEqual(generator.callCount, 6, "combined 1回 + 5セクション個別生成")
        let parsed = StockSummary.parse(result)
        XCTAssertEqual(parsed?.topic, "トピック本文")
        XCTAssertEqual(parsed?.purpose, "目的本文")
        XCTAssertEqual(parsed?.mainMessage, "主張本文")
        XCTAssertEqual(parsed?.summaryLines, ["要約1", "要約2"])
        XCTAssertEqual(parsed?.learningLines, ["学び本文"])
    }

    func test_summarize_フォールバック時に空で返ったセクションだけ再生成する() async throws {
        let generator = MockTextGenerator()
        generator.responses = [
            "壊れた出力",       // combined: parse 失敗
            "", "トピック本文",  // topic: 1回目空 → 再生成
            "目的本文", "主張本文", "要約", "学び",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertEqual(StockSummary.parse(result)?.topic, "トピック本文")
    }

    func test_summarize_フォールバックしても空なら固定見出しは必ず組み立てられる() async throws {
        // モデルが常に空を返しても、見出し(青表示の元)は必ず揃い parse は成功する
        let generator = MockTextGenerator()
        generator.responses = []
        generator.result = "" // 常に空
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertNotNil(StockSummary.parse(result), "空でも4見出しが揃い parse できること(=見出しは常に青)")
    }

    func test_summarize_フォールバック時にセクション本文へ紛れた見出し行を除去する() async throws {
        let generator = MockTextGenerator()
        generator.responses = [
            "壊れた出力",
            "## 何についての記事か\n実際のトピック", "目的本文", "主張本文", "要約", "学び",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertEqual(StockSummary.parse(result)?.topic, "実際のトピック", "本文に紛れた見出し行は除去する")
    }

    func test_summarize_フォールバック時に要約は20行以内へ切り詰める() async throws {
        let bodyLines = (1...30).map { "行\($0)" }.joined(separator: "\n")
        let generator = MockTextGenerator()
        generator.responses = [
            "壊れた出力",
            "トピック本文", "目的本文", "主張本文", bodyLines, "学び",
        ]
        let summarizer = StockSummarizer(generator: generator)

        let result = try await summarizer.summarize(title: "タイトル", text: aiInputText)

        XCTAssertLessThanOrEqual(StockSummary.parse(result)?.summaryLines.count ?? 0, 20)
    }

    // MARK: - summarize(url:title:) URL からのフェッチ

    func test_summarizeFromURL_ページ本文を取得してから要約する() async throws {
        let fetchedText = "Fetched body text " + String(repeating: "本文", count: 51)
        MockURLProtocol.requestHandler = { _ in
            (200, Data("<html><body><p>\(fetchedText)</p></body></html>".utf8))
        }
        let generator = MockTextGenerator()
        generator.responses = [completeResponse]
        let summarizer = StockSummarizer(generator: generator)

        _ = try await summarizer.summarize(url: URL(string: "https://example.com/a")!, title: "T", session: .mock())

        XCTAssertTrue(generator.receivedPrompts[0].contains(fetchedText))
    }
}
