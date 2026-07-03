import Foundation

enum StockSummaryGenerationError: Error, LocalizedError, Equatable {
    case aiUnavailable
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .aiUnavailable:
            return "この端末ではローカル AI を利用できません(iOS 27 以上と Apple Intelligence の有効化が必要です)"
        case .invalidURL:
            return "URL が不正です"
        }
    }
}

final class StockStore: ObservableObject {
    @Published var categories: [StockCategory] = []
    @Published var stocks: [Stock] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var sortAscending: Bool {
        didSet { UserDefaults.standard.set(sortAscending, forKey: DefaultsKeys.stockSortAscending) }
    }

    /// テスト用の差し替えポイント。デフォルトはオンデバイス Foundation Models(利用不可なら nil)。
    var makeSummaryGenerator: () -> (any TextGenerating)? = { LocalAI.makeGenerator() }

    // MARK: - 要約キュー
    // View(戻るボタン等)のライフサイクルに依存せず Store が持つことで、
    // 画面遷移後もキュー処理を継続できる。オンデバイス AI は同時に1リクエストしか
    // 処理できないため(LanguageModelSession.Error.concurrentRequests)、常に直列実行する。

    /// 実行待ちのストック ID(先頭が次に実行される)
    @Published private(set) var pendingSummaryStockIds: [Int] = []
    /// 現在生成中のストック ID
    @Published private(set) var currentlySummarizingStockId: Int?
    /// ストックIDごとの直近の要約失敗メッセージ
    @Published private(set) var summaryErrors: [Int: String] = [:]

    private var summaryQueueTask: Task<Void, Never>?
    private var isSummaryQueuePaused = false

    private var client: (any APIClientProtocol)?

    init() {
        self.sortAscending = UserDefaults.standard.bool(forKey: DefaultsKeys.stockSortAscending)
    }

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    /// 指定カテゴリのストックを stocked_at でソートして返す（sortAscending に連動）
    func stocks(in categoryId: Int) -> [Stock] {
        let filtered = stocks.filter { $0.category_id == categoryId }
        return filtered.sorted { a, b in
            sortAscending ? a.stocked_at < b.stocked_at : a.stocked_at > b.stocked_at
        }
    }

    @MainActor
    func fetchAll() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let categoriesTask = StockRepository(client: client).fetchCategories()
            async let stocksTask = StockRepository(client: client).fetchAll()
            categories = try await categoriesTask
            stocks = try await stocksTask
        } catch {
            self.error = error
        }
    }

    /// URL が既にストック済みの場合はサーバー側で no-op になる(既存を返す)。
    /// 戻り値のストックをローカルへ反映する。失敗時は throw する(呼び出し元がエラー表示 or 黙殺を選ぶ)。
    @MainActor
    @discardableResult
    func createStock(url: String, title: String? = nil, source: String? = nil, category: String? = nil) async throws -> Stock {
        guard let client else { throw APIError.invalidURL }
        let stock = try await StockRepository(client: client).create(url: url, title: title, source: source, category: category)
        upsertLocally(stock)
        return stock
    }

    @MainActor
    func updateStock(id: Int, title: String, category: String) async throws {
        guard let client else { return }
        let updated = try await StockRepository(client: client).update(id: id, title: title, category: category)
        upsertLocally(updated)
        await removeEmptyCategoriesLocally()
    }

    @MainActor
    func deleteStock(id: Int) async throws {
        guard let client else { return }
        try await StockRepository(client: client).delete(id: id)
        stocks.removeAll { $0.id == id }
        await removeEmptyCategoriesLocally()
    }

    @MainActor
    func saveSummary(id: Int, summary: String) async throws {
        guard let client else { return }
        try await StockRepository(client: client).saveSummary(id: id, summary: summary)
        if let idx = stocks.firstIndex(where: { $0.id == id }) {
            stocks[idx] = stocks[idx].updating(summary: summary)
        }
    }

    /// 保存済みの翻訳を取得する(未保存・取得失敗時は nil)
    @MainActor
    func fetchTranslation(id: Int) async -> StockTranslationPayload? {
        guard let client else { return nil }
        return try? await StockRepository(client: client).fetchTranslation(id: id)
    }

    /// 翻訳を保存する(UPSERT。再翻訳時の上書きもこのメソッドを使う)
    @MainActor
    func saveTranslation(id: Int, segments: String) async throws {
        guard let client else { return }
        try await StockRepository(client: client).saveTranslation(id: id, segments: segments)
        if let idx = stocks.firstIndex(where: { $0.id == id }) {
            stocks[idx] = stocks[idx].updating(hasTranslation: true)
        }
    }

    /// 指定したストック 1 件の要約を生成して保存する。ユーザーの明示的なボタン操作からのみ呼ばれる
    /// (起動時・フォアグラウンド復帰時の自動生成は行わない)。失敗時は throw し、呼び出し元(View)が表示する。
    @MainActor
    func generateSummary(for stockId: Int, session: URLSession = .shared) async throws {
        guard let stock = stocks.first(where: { $0.id == stockId }) else { return }
        guard let generator = makeSummaryGenerator() else { throw StockSummaryGenerationError.aiUnavailable }
        guard let url = URL(string: stock.url) else { throw StockSummaryGenerationError.invalidURL }

        let summarizer = StockSummarizer(generator: generator)
        try await BackgroundExecution.run(name: "Stock.summarize") {
            let summary = try await summarizer.summarize(url: url, title: stock.title, session: session)
            try await saveSummary(id: stockId, summary: summary)
        }
    }

    /// 要約をキューに追加する(fire-and-forget)。View のライフサイクル(戻るボタン等)に
    /// 依存せず Store が保持し続けるため、画面遷移後もキュー処理を継続する。
    /// 既に生成中/待機中/生成済みのストックは無視する。
    @MainActor
    func requestSummary(for stockId: Int, session: URLSession = .shared) {
        guard stocks.first(where: { $0.id == stockId })?.summary == nil else { return }
        guard currentlySummarizingStockId != stockId, !pendingSummaryStockIds.contains(stockId) else { return }
        summaryErrors[stockId] = nil
        pendingSummaryStockIds.append(stockId)
        driveSummaryQueue(session: session)
    }

    /// 翻訳を優先させるため、実行中の要約があれば中断してキュー処理を一時停止する。
    /// オンデバイス AI は同時に1リクエストしか処理できないための措置(#126 参照)。
    /// 中断された要約は再開時に最初からやり直す(オンデバイスモデルに部分再開の手段が無いため)。
    ///
    /// summaryQueueTask はここで同期的に nil クリアする(キャンセルされたタスク自身の後片付けを
    /// 待たない)。そうしないと、キャンセル後すぐに resumeSummaryQueueAfterTranslation で新しい
    /// タスクを開始した場合、遅れて実行される旧タスクの後片付けが新タスクの参照を誤って
    /// クリアしてしまうレースが起こり得る(driveSummaryQueue の再入防止ガードが壊れる)。
    @MainActor
    func pauseSummaryQueueForTranslation() {
        isSummaryQueuePaused = true
        summaryQueueTask?.cancel()
        summaryQueueTask = nil
    }

    /// 翻訳完了後、要約キューを再開する。
    @MainActor
    func resumeSummaryQueueAfterTranslation(session: URLSession = .shared) {
        isSummaryQueuePaused = false
        driveSummaryQueue(session: session)
    }

    /// エラーアラートを閉じた後の表示クリア用。
    @MainActor
    func clearSummaryError(for stockId: Int) {
        summaryErrors[stockId] = nil
    }

    @MainActor
    private func driveSummaryQueue(session: URLSession) {
        guard summaryQueueTask == nil, !isSummaryQueuePaused else { return }
        summaryQueueTask = Task { [weak self] in
            await self?.runSummaryQueue(session: session)
            // pauseSummaryQueueForTranslation は自分で summaryQueueTask を同期的にクリアするため、
            // キャンセルされて戻ってきた場合はここで触らない(新しいタスクの参照を壊さないため)。
            if !Task.isCancelled {
                self?.summaryQueueTask = nil
            }
        }
    }

    @MainActor
    private func runSummaryQueue(session: URLSession) async {
        while !isSummaryQueuePaused, !pendingSummaryStockIds.isEmpty {
            let stockId = pendingSummaryStockIds.removeFirst()
            currentlySummarizingStockId = stockId
            do {
                try await generateSummary(for: stockId, session: session)
            } catch is CancellationError {
                // 翻訳優先のため中断された。やり直せるようキュー先頭へ戻して終了する。
                pendingSummaryStockIds.insert(stockId, at: 0)
                currentlySummarizingStockId = nil
                return
            } catch {
                summaryErrors[stockId] = error.localizedDescription
            }
            currentlySummarizingStockId = nil
        }
    }

    @MainActor
    func reorderCategories(from source: IndexSet, to destination: Int) async throws {
        guard let client else { return }
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        let ids = reordered.map { $0.id }
        try await StockRepository(client: client).reorderCategories(ids: ids)
        categories = reordered
    }

    // MARK: - Private

    @MainActor
    private func upsertLocally(_ stock: Stock) {
        if let idx = stocks.firstIndex(where: { $0.id == stock.id }) {
            stocks[idx] = stock
        } else {
            stocks.append(stock)
        }
        if !categories.contains(where: { $0.id == stock.category_id }) {
            // カテゴリがまだローカルにない(新規作成された)場合は一覧を取り直す
            Task { await refreshCategories() }
        }
    }

    @MainActor
    private func refreshCategories() async {
        guard let client else { return }
        categories = (try? await StockRepository(client: client).fetchCategories()) ?? categories
    }

    /// ストックが 0 件になったカテゴリはサーバー側で自動削除されるため、ローカル一覧も同期する
    @MainActor
    private func removeEmptyCategoriesLocally() async {
        await refreshCategories()
    }
}
