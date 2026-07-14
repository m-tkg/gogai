import XCTest
@testable import Gogai

final class StockStoreTests: StoreTestCase {
    private static let aiSizedText = String(repeating: "本文", count: 51)
    private static let aiSizedHTML = Data("<html><body><p>\(aiSizedText)</p></body></html>".utf8)

    var store: StockStore!

    override func setUp() {
        super.setUp()
        store = StockStore()
        store.configure(with: client)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.stockSortAscending)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.stockSummaryQueue)
        super.tearDown()
    }

    private func makeStock(id: Int = 1, categoryId: Int = 1, categoryName: String = "Tech", stockedAt: String = "2024-01-01T00:00:00Z") -> Stock {
        Stock(id: id, url: "https://example.com/\(id)", title: "Title \(id)", source: "Tech",
              category_id: categoryId, category_name: categoryName, summary: nil,
              has_translation: false, stocked_at: stockedAt, created_at: stockedAt)
    }

    private func makeCategory(id: Int = 1, name: String = "Tech", displayOrder: Int = 0, stockCount: Int = 1) -> StockCategory {
        StockCategory(id: id, name: name, display_order: displayOrder, created_at: "2024-01-01T00:00:00Z", stock_count: stockCount)
    }

    @MainActor
    func test_fetchAll_updatesCategoriesAndStocks() async {
        let categories = [makeCategory()]
        let stocks = [makeStock()]
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/api/stock-categories") {
                return (200, try JSONEncoder().encode(categories))
            }
            return (200, try JSONEncoder().encode(stocks))
        }

        await store.fetchAll()

        XCTAssertEqual(store.categories.count, 1)
        XCTAssertEqual(store.stocks.count, 1)
        XCTAssertNil(store.error)
    }

    @MainActor
    func test_createStock_appendsToStocks() async throws {
        store.stocks.removeAll()
        let created = makeStock(id: 5)
        MockURLProtocol.requestHandler = { _ in (201, try JSONEncoder().encode(created)) }

        let result = try await store.createStock(url: "https://example.com/5", source: "Tech")

        XCTAssertEqual(result.id, 5)
        XCTAssertEqual(store.stocks.count, 1)
    }

    @MainActor
    func test_createStock_duplicateUrl_updatesExistingRatherThanAppending() async throws {
        store.stocks = [makeStock(id: 1)]
        let existing = makeStock(id: 1)
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(existing)) }

        _ = try await store.createStock(url: "https://example.com/1", source: "Tech")

        XCTAssertEqual(store.stocks.count, 1)
    }

    @MainActor
    func test_createStock_failure_throws() async {
        MockURLProtocol.requestHandler = { _ in (500, Data()) }

        do {
            _ = try await store.createStock(url: "https://example.com/1", source: "Tech")
            XCTFail("エラーが throw されるはず")
        } catch {
            // 期待通り
        }
    }

    @MainActor
    func test_deleteStock_removesFromStocks() async throws {
        store.stocks = [makeStock(id: 1), makeStock(id: 2)]
        store.categories = [makeCategory()]
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "DELETE" { return (204, Data()) }
            return (200, try JSONEncoder().encode([StockCategory]()))
        }

        try await store.deleteStock(id: 1)

        XCTAssertEqual(store.stocks.count, 1)
        XCTAssertEqual(store.stocks[0].id, 2)
    }

    @MainActor
    func test_updateStock_replacesInStocks() async throws {
        store.stocks = [makeStock(id: 1, categoryName: "Tech")]
        store.categories = [makeCategory()]
        let updated = makeStock(id: 1, categoryName: "あとで読む")
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "PUT" { return (200, try JSONEncoder().encode(updated)) }
            return (200, try JSONEncoder().encode([StockCategory]()))
        }

        try await store.updateStock(id: 1, title: "A2", category: "あとで読む")

        XCTAssertEqual(store.stocks[0].category_name, "あとで読む")
    }

    @MainActor
    func test_reorderCategories_updatesLocalOrder() async throws {
        store.categories = [makeCategory(id: 1, name: "A", displayOrder: 0), makeCategory(id: 2, name: "B", displayOrder: 1)]
        MockURLProtocol.requestHandler = { _ in (204, Data()) }

        try await store.reorderCategories(from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(store.categories[0].id, 2)
        XCTAssertEqual(store.categories[1].id, 1)
    }

    // MARK: - stocks(in:) ソート

    @MainActor
    func test_stocksInCategory_sortsDescendingByDefault() {
        store.stocks = [
            makeStock(id: 1, stockedAt: "2024-01-01T00:00:00Z"),
            makeStock(id: 2, stockedAt: "2024-01-03T00:00:00Z"),
            makeStock(id: 3, stockedAt: "2024-01-02T00:00:00Z"),
        ]

        let sorted = store.stocks(in: 1)

        XCTAssertEqual(sorted.map { $0.id }, [2, 3, 1])
    }

    @MainActor
    func test_stocksInCategory_sortsAscending_whenSortAscendingIsTrue() {
        store.stocks = [
            makeStock(id: 1, stockedAt: "2024-01-01T00:00:00Z"),
            makeStock(id: 2, stockedAt: "2024-01-03T00:00:00Z"),
        ]
        store.sortAscending = true

        let sorted = store.stocks(in: 1)

        XCTAssertEqual(sorted.map { $0.id }, [1, 2])
    }

    @MainActor
    func test_stocksInCategory_filtersByCategoryId() {
        store.stocks = [makeStock(id: 1, categoryId: 1), makeStock(id: 2, categoryId: 2)]

        XCTAssertEqual(store.stocks(in: 1).map { $0.id }, [1])
    }

    // MARK: - generateSummary(for:)（ボタン起点の単体生成）

    @MainActor
    func test_generateSummary_指定したストックにサマリーを保存する() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = MockTextGenerator()
        generator.result = "## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/summary") { return (204, Data()) }
            return (200, Self.aiSizedHTML)
        }

        try await store.generateSummary(for: 1, session: .mock())

        XCTAssertEqual(generator.callCount, 1)
        XCTAssertNotNil(store.stocks[0].summary)
    }

    @MainActor
    func test_generateSummary_進捗ログを保存する() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = MockTextGenerator()
        generator.result = "## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/summary") { return (204, Data()) }
            return (200, Self.aiSizedHTML)
        }

        try await store.generateSummary(for: 1, session: .mock())

        let logs = store.summaryProgressLogs[1] ?? []
        XCTAssertTrue(logs.contains("要約処理を開始"))
        XCTAssertTrue(logs.contains { $0.contains("記事本文を取得中") })
        XCTAssertTrue(logs.contains { $0.contains("要約リクエスト送信中") })
        XCTAssertTrue(logs.contains("生成した要約をサーバーへ保存中"))
        XCTAssertTrue(logs.contains("要約の保存が完了"))
    }

    @MainActor
    func test_generateSummary_AI利用不可ならthrowする() async {
        store.stocks = [makeStock(id: 1)]
        store.makeSummaryGenerator = { nil }

        do {
            try await store.generateSummary(for: 1, session: .mock())
            XCTFail("aiUnavailable が throw されるはず")
        } catch let error as LocalAIError {
            XCTAssertEqual(error, .aiUnavailable)
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
        XCTAssertNil(store.stocks[0].summary)
    }

    @MainActor
    func test_generateSummary_生成失敗はthrowし保存しない() async {
        store.stocks = [makeStock(id: 1)]
        let generator = MockTextGenerator()
        generator.error = URLError(.badServerResponse)
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = { _ in (200, Self.aiSizedHTML) }

        do {
            try await store.generateSummary(for: 1, session: .mock())
            XCTFail("エラーが throw されるはず")
        } catch {
            // 期待通り
        }
        XCTAssertNil(store.stocks[0].summary)
    }

    @MainActor
    func test_generateSummary_存在しないストックIDは何もしない() async throws {
        store.stocks = []
        let generator = MockTextGenerator()
        store.makeSummaryGenerator = { generator }

        try await store.generateSummary(for: 999, session: .mock())

        XCTAssertEqual(generator.callCount, 0)
    }

    // MARK: - requestSummary(for:)（キュー投入。戻るボタンやタスクスイッチに影響されない）

    /// generate() を外部から解放するまでブロックし、呼び出し順を検証できるジェネレーター。
    /// generate() を外部から解放するまでブロックするジェネレーター。
    /// 呼び出しごとに専用の CheckedContinuation を使う(AsyncStream は同一ストリームに対して
    /// 呼び出しごとに新しい makeAsyncIterator() を作ると値の受け渡しが不安定になるため使わない)。
    private final class GatedTextGenerator: TextGenerating, @unchecked Sendable {
        private(set) var callCount = 0
        let calledStream: AsyncStream<Int>
        private let calledContinuation: AsyncStream<Int>.Continuation
        private var pendingRelease: CheckedContinuation<Void, Never>?

        init() {
            (calledStream, calledContinuation) = AsyncStream<Int>.makeStream()
        }

        func generate(instructions: String, prompt: String) async throws -> String {
            callCount += 1
            calledContinuation.yield(callCount)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pendingRelease = continuation
            }
            if Task.isCancelled {
                throw CancellationError()
            }
            return "## 何についての記事か\nA\n## 何の目的で書かれたか\nB\n## 筆者が一番伝えたいこと\nC\n## 要約(20行以内)\nD"
        }

        func release() {
            pendingRelease?.resume()
            pendingRelease = nil
        }
    }

    private func summaryRequestHandler(_ request: URLRequest) throws -> (Int, Data) {
        if request.url!.path.hasSuffix("/summary") { return (204, Data()) }
        return (200, Self.aiSizedHTML)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func test_requestSummary_2件目は1件目が完了するまで開始しない() async throws {
        store.stocks = [makeStock(id: 1), makeStock(id: 2)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        store.requestSummary(for: 2, session: .mock())

        var iterator = generator.calledStream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(store.currentlySummarizingStockId, 1)
        XCTAssertEqual(store.pendingSummaryStockIds, [2], "2件目は1件目の完了を待つ")

        generator.release()
        let second = await iterator.next()
        XCTAssertEqual(second, 2)
        XCTAssertEqual(store.currentlySummarizingStockId, 2)
        XCTAssertEqual(store.pendingSummaryStockIds, [])

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
        XCTAssertNotNil(store.stocks.first(where: { $0.id == 1 })?.summary)
        XCTAssertNotNil(store.stocks.first(where: { $0.id == 2 })?.summary)
    }

    @MainActor
    func test_requestSummary_既にキュー済み_実行中のIDは重複追加しない() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        store.requestSummary(for: 1, session: .mock())

        XCTAssertEqual(store.pendingSummaryStockIds, [], "実行中のIDは再投入しない")
        XCTAssertEqual(generator.callCount, 1)

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
    }

    @MainActor
    func test_requestSummary_既に要約済みのストックは無視する() {
        var stock = makeStock(id: 1)
        stock = stock.updating(summary: .set("既存の要約"))
        store.stocks = [stock]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }

        store.requestSummary(for: 1, session: .mock())

        XCTAssertEqual(store.pendingSummaryStockIds, [])
        XCTAssertNil(store.currentlySummarizingStockId)
    }

    @MainActor
    func test_requestSummary_forceがtrueなら要約済みのストックも再度キューに入れる() async throws {
        var stock = makeStock(id: 1)
        stock = stock.updating(summary: .set("既存の要約"))
        store.stocks = [stock]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, force: true, session: .mock())

        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertEqual(store.currentlySummarizingStockId, 1, "force: true なら要約済みでもキューに入る")

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        XCTAssertNotEqual(store.stocks[0].summary, "既存の要約", "新しい要約で上書きされる")
    }

    @MainActor
    func test_requestSummary_失敗しても次のキューは処理を続ける() async throws {
        store.stocks = [makeStock(id: 1), makeStock(id: 2)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = { request in
            // 本文取得は両方成功させ、generate() には必ず到達させる。
            // 1件目だけ要約の保存(PUT .../1/summary)を失敗させる。
            if request.url!.path.hasSuffix("/1/summary") { return (500, Data()) }
            if request.url!.path.hasSuffix("/summary") { return (204, Data()) }
            return (200, Self.aiSizedHTML)
        }

        store.requestSummary(for: 1, session: .mock())
        store.requestSummary(for: 2, session: .mock())

        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        generator.release()
        let second = await iterator.next()
        XCTAssertEqual(second, 2, "1件目が失敗しても2件目は実行される")

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
        XCTAssertNotNil(store.summaryErrors[1])
    }

    // MARK: - pauseSummaryQueueForTranslation / resumeSummaryQueueAfterTranslation（翻訳優先）

    @MainActor
    func test_pauseSummaryQueueForTranslation_実行中の要約を中断しキュー先頭へ戻す() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertEqual(store.currentlySummarizingStockId, 1)

        store.pauseSummaryQueueForTranslation()
        // 中断された generate() 呼び出しはキャンセル検知のため解放してやる必要がある(そうしないと
        // モック内で永久に await したままになり、以降のテストに影響する)。
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        XCTAssertNil(store.currentlySummarizingStockId)
        XCTAssertEqual(store.pendingSummaryStockIds, [1], "中断された分はやり直すためキュー先頭へ戻る")
        XCTAssertNil(store.stocks.first(where: { $0.id == 1 })?.summary, "保存はされない")
    }

    @MainActor
    func test_resumeSummaryQueueAfterTranslation_中断した要約を再開する() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        store.pauseSummaryQueueForTranslation()
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        store.resumeSummaryQueueAfterTranslation(session: .mock())
        let restarted = await iterator.next()
        XCTAssertEqual(restarted, 2, "中断前の1回 + 再開後の1回で計2回呼ばれる(最初からやり直し)")

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
        XCTAssertNil(store.summaryErrors[1])
        XCTAssertEqual(store.pendingSummaryStockIds, [])
        XCTAssertNotNil(store.stocks.first(where: { $0.id == 1 })?.summary)
    }

    // MARK: - cancelSummary(for:)（キュー内の個別ストックのキャンセル）

    @MainActor
    func test_cancelSummary_キュー内の未実行ストックを削除する() async throws {
        store.stocks = [makeStock(id: 1), makeStock(id: 2)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        store.requestSummary(for: 2, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertEqual(store.pendingSummaryStockIds, [2])

        store.cancelSummary(for: 2)

        XCTAssertEqual(store.pendingSummaryStockIds, [], "キャンセルしたストックはキューから消える")

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
        XCTAssertNotNil(store.stocks.first(where: { $0.id == 1 })?.summary)
        XCTAssertNil(store.stocks.first(where: { $0.id == 2 })?.summary)
    }

    @MainActor
    func test_cancelSummary_実行中のストックはキャンセル後に再投入されない() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertEqual(store.currentlySummarizingStockId, 1)

        store.cancelSummary(for: 1)
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        XCTAssertEqual(store.pendingSummaryStockIds, [], "キャンセルされた分は一時停止と違い再投入されない")
        XCTAssertNil(store.stocks.first(where: { $0.id == 1 })?.summary)
    }

    // MARK: - pauseSummaryQueue / resumeSummaryQueue（ユーザー起点の一時停止）

    @MainActor
    func test_pauseSummaryQueue_実行中の要約を中断しキュー先頭へ戻す() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()

        store.pauseSummaryQueue()
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        XCTAssertTrue(store.isSummaryQueuePausedByUser)
        XCTAssertEqual(store.pendingSummaryStockIds, [1], "一時停止した分はやり直すためキュー先頭へ戻る")
        XCTAssertNil(store.stocks.first(where: { $0.id == 1 })?.summary)
    }

    @MainActor
    func test_pauseSummaryQueue_一時停止中は新規キューを開始しない() {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.pauseSummaryQueue()
        store.requestSummary(for: 1, session: .mock())

        XCTAssertEqual(store.pendingSummaryStockIds, [1])
        XCTAssertNil(store.currentlySummarizingStockId)
        XCTAssertEqual(generator.callCount, 0)
    }

    @MainActor
    func test_resumeSummaryQueue_一時停止解除で処理を再開する() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.pauseSummaryQueue()
        store.requestSummary(for: 1, session: .mock())
        XCTAssertEqual(generator.callCount, 0)

        store.resumeSummaryQueue(session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, 1)
        XCTAssertFalse(store.isSummaryQueuePausedByUser)

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
        XCTAssertNotNil(store.stocks.first(where: { $0.id == 1 })?.summary)
    }

    @MainActor
    func test_resumeSummaryQueue_翻訳優先の一時停止中は開始しない() {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.pauseSummaryQueueForTranslation()
        store.requestSummary(for: 1, session: .mock())
        store.resumeSummaryQueue(session: .mock())

        XCTAssertEqual(generator.callCount, 0, "翻訳優先の一時停止中はユーザーの resume では開始しない")
        XCTAssertEqual(store.pendingSummaryStockIds, [1])
    }

    // MARK: - 要約キューの永続化(アプリ終了後の再開)

    @MainActor
    func test_requestSummary_キューに入れるとUserDefaultsへ永続化する() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())

        XCTAssertEqual(UserDefaults.standard.array(forKey: DefaultsKeys.stockSummaryQueue) as? [Int], [1])

        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
    }

    @MainActor
    func test_要約が完了すると永続化キューから取り除かれる() async throws {
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.requestSummary(for: 1, session: .mock())
        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        XCTAssertEqual(UserDefaults.standard.array(forKey: DefaultsKeys.stockSummaryQueue) as? [Int] ?? [], [])
    }

    @MainActor
    func test_resumePersistedSummaryQueueIfNeeded_永続化されたキューを再開する() async throws {
        UserDefaults.standard.set([1], forKey: DefaultsKeys.stockSummaryQueue)
        store.stocks = [makeStock(id: 1)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = summaryRequestHandler

        store.resumePersistedSummaryQueueIfNeeded(session: .mock())

        var iterator = generator.calledStream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(store.currentlySummarizingStockId, 1)

        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }
        XCTAssertNotNil(store.stocks.first(where: { $0.id == 1 })?.summary)
    }

    @MainActor
    func test_resumePersistedSummaryQueueIfNeeded_既に要約済みのIDは再開しない() {
        UserDefaults.standard.set([1], forKey: DefaultsKeys.stockSummaryQueue)
        var stock = makeStock(id: 1)
        stock = stock.updating(summary: .set("既存の要約"))
        store.stocks = [stock]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }

        store.resumePersistedSummaryQueueIfNeeded(session: .mock())

        XCTAssertEqual(store.pendingSummaryStockIds, [])
        XCTAssertNil(store.currentlySummarizingStockId)
        XCTAssertEqual(generator.callCount, 0)
    }

    @MainActor
    func test_resumePersistedSummaryQueueIfNeeded_存在しないストックIDは無視する() {
        UserDefaults.standard.set([999], forKey: DefaultsKeys.stockSummaryQueue)
        store.stocks = []
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }

        store.resumePersistedSummaryQueueIfNeeded(session: .mock())

        XCTAssertEqual(store.pendingSummaryStockIds, [])
        XCTAssertNil(store.currentlySummarizingStockId)
    }

    // MARK: - restorePersistedSummaryErrorsIfNeeded（永続化された要約エラーの復元）

    @MainActor
    func test_restorePersistedSummaryErrorsIfNeeded_要約未生成のストックのエラーを復元する() {
        UserDefaults.standard.set(["1": "エラーメッセージ"], forKey: DefaultsKeys.stockSummaryErrors)
        store.stocks = [makeStock(id: 1)]

        store.restorePersistedSummaryErrorsIfNeeded()

        XCTAssertEqual(store.summaryErrors[1], "エラーメッセージ")
    }

    @MainActor
    func test_restorePersistedSummaryErrorsIfNeeded_要約済みのストックは復元しない() {
        UserDefaults.standard.set(["1": "エラーメッセージ"], forKey: DefaultsKeys.stockSummaryErrors)
        var stock = makeStock(id: 1)
        stock = stock.updating(summary: .set("既存の要約"))
        store.stocks = [stock]

        store.restorePersistedSummaryErrorsIfNeeded()

        XCTAssertNil(store.summaryErrors[1])
    }

    @MainActor
    func test_restorePersistedSummaryErrorsIfNeeded_存在しないストックIDは復元しない() {
        UserDefaults.standard.set(["999": "エラーメッセージ"], forKey: DefaultsKeys.stockSummaryErrors)
        store.stocks = []

        store.restorePersistedSummaryErrorsIfNeeded()

        XCTAssertTrue(store.summaryErrors.isEmpty)
    }

    // MARK: - clearSummaryError（エラーアラートを閉じた後の表示クリア）

    @MainActor
    func test_clearSummaryError_指定したストックのエラーだけ消す() async throws {
        store.stocks = [makeStock(id: 1), makeStock(id: 2)]
        let generator = GatedTextGenerator()
        store.makeSummaryGenerator = { generator }
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/summary") { return (500, Data()) }
            return (200, Self.aiSizedHTML)
        }

        store.requestSummary(for: 1, session: .mock())
        store.requestSummary(for: 2, session: .mock())

        var iterator = generator.calledStream.makeAsyncIterator()
        _ = await iterator.next()
        generator.release()
        _ = await iterator.next()
        generator.release()
        await waitUntil { store.currentlySummarizingStockId == nil }

        XCTAssertNotNil(store.summaryErrors[1])
        XCTAssertNotNil(store.summaryErrors[2])

        store.clearSummaryError(for: 1)

        XCTAssertNil(store.summaryErrors[1])
        XCTAssertNotNil(store.summaryErrors[2])
    }

    // MARK: - sortAscending の永続化

    func test_sortAscending_defaultsToFalse() {
        XCTAssertFalse(store.sortAscending)
    }

    @MainActor
    func test_sortAscending_persistsToUserDefaults() {
        store.sortAscending = true

        XCTAssertTrue(UserDefaults.standard.bool(forKey: DefaultsKeys.stockSortAscending))
    }

    // MARK: - キャッシュ

    private func makeTmpCache() -> (AppCache, URL) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return (AppCache(directory: tmpDir), tmpDir)
    }

    func test_init_loadsStocksAndCategoriesFromCache() {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cachedStocks = [makeStock(id: 42)]
        let cachedCategories = [makeCategory(id: 7, name: "Cached")]
        testCache.saveStocks(cachedStocks)
        testCache.saveStockCategories(cachedCategories)

        let storeWithCache = StockStore(cache: testCache)

        XCTAssertEqual(storeWithCache.stocks.count, 1, "起動時にキャッシュからストックを読み込むこと")
        XCTAssertEqual(storeWithCache.stocks[0].id, 42)
        XCTAssertEqual(storeWithCache.categories.count, 1, "起動時にキャッシュからカテゴリを読み込むこと")
        XCTAssertEqual(storeWithCache.categories[0].id, 7)
    }

    @MainActor
    func test_fetchAll_savesToCache() async {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let storeWithCache = StockStore(cache: testCache)
        storeWithCache.configure(with: client)

        let categories = [makeCategory()]
        let stocks = [makeStock()]
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("/api/stock-categories") {
                return (200, try JSONEncoder().encode(categories))
            }
            return (200, try JSONEncoder().encode(stocks))
        }

        await storeWithCache.fetchAll()

        XCTAssertEqual(testCache.loadStocks().count, 1, "fetchAll 後にストックのキャッシュが保存されること")
        XCTAssertEqual(testCache.loadStockCategories().count, 1, "fetchAll 後にカテゴリのキャッシュが保存されること")
    }
}
