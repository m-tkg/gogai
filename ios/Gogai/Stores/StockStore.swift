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
    @Published private(set) var pendingSummaryStockIds: [Int] = [] {
        didSet { persistSummaryQueueSnapshot() }
    }
    /// 現在生成中のストック ID
    @Published private(set) var currentlySummarizingStockId: Int? {
        didSet { persistSummaryQueueSnapshot() }
    }
    /// ストックIDごとの直近の要約失敗メッセージ
    @Published private(set) var summaryErrors: [Int: String] = [:]
    /// ユーザーが一時停止ボタンで止めたかどうか(翻訳優先による一時停止とは別軸)
    @Published private(set) var isSummaryQueuePausedByUser = false

    private var summaryQueueTask: Task<Void, Never>?
    /// 翻訳優先のため自動的に一時停止しているか(#126 参照)
    private var isPausedForTranslation = false
    /// 実行中にキャンセルされ、完了後もキューへ戻さない対象(一時停止との違いはここ)
    private var cancelledSummaryStockIds: Set<Int> = []

    /// 実際にキューを進めてよいか(翻訳優先 or ユーザー操作のどちらかで停止していれば false)
    private var isSummaryQueuePaused: Bool {
        isPausedForTranslation || isSummaryQueuePausedByUser
    }

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
        isPausedForTranslation = true
        summaryQueueTask?.cancel()
        summaryQueueTask = nil
    }

    /// 翻訳完了後、要約キューを再開する。ユーザーが一時停止中の場合は再開しない。
    @MainActor
    func resumeSummaryQueueAfterTranslation(session: URLSession = .shared) {
        isPausedForTranslation = false
        driveSummaryQueue(session: session)
    }

    /// ユーザー操作による一時停止。実行中の要約があれば中断し、キュー先頭へ戻す(やり直せるように)。
    /// 翻訳優先の一時停止とは独立して管理するため、翻訳が終わっても自動再開されない。
    @MainActor
    func pauseSummaryQueue() {
        isSummaryQueuePausedByUser = true
        summaryQueueTask?.cancel()
        summaryQueueTask = nil
    }

    /// ユーザー操作による一時停止を解除する。翻訳優先の一時停止が別途かかっている場合は
    /// (isSummaryQueuePaused が true のままなので)driveSummaryQueue 側のガードで開始されない。
    @MainActor
    func resumeSummaryQueue(session: URLSession = .shared) {
        isSummaryQueuePausedByUser = false
        driveSummaryQueue(session: session)
    }

    /// キュー内の特定のストックをキャンセルする。待機中ならキューから外すだけ、
    /// 生成中なら中断し、一時停止と違い完了後もキューへ戻さない(cancelledSummaryStockIds で判別)。
    @MainActor
    func cancelSummary(for stockId: Int) {
        pendingSummaryStockIds.removeAll { $0 == stockId }
        summaryErrors[stockId] = nil
        guard currentlySummarizingStockId == stockId else { return }
        cancelledSummaryStockIds.insert(stockId)
        summaryQueueTask?.cancel()
        summaryQueueTask = nil
    }

    /// エラーアラートを閉じた後の表示クリア用。
    @MainActor
    func clearSummaryError(for stockId: Int) {
        summaryErrors[stockId] = nil
    }

    /// アプリ終了(強制終了含む)後の再起動時に、永続化された要約キューを再開する。
    /// fetchAll() で stocks を読み込んだ後に呼ぶこと。
    /// 既に要約済み/削除済みのストック ID は除外する(他端末で完了している場合があるため)。
    @MainActor
    func resumePersistedSummaryQueueIfNeeded(session: URLSession = .shared) {
        guard pendingSummaryStockIds.isEmpty, currentlySummarizingStockId == nil else { return }
        let persistedIds = UserDefaults.standard.array(forKey: DefaultsKeys.stockSummaryQueue) as? [Int] ?? []
        let restoredIds = persistedIds.filter { id in
            guard let stock = stocks.first(where: { $0.id == id }) else { return false }
            return stock.summary == nil
        }
        guard !restoredIds.isEmpty else { return }
        pendingSummaryStockIds = restoredIds
        driveSummaryQueue(session: session)
    }

    /// 現在の要約キュー(生成中 + 待機中)を UserDefaults へ保存する。
    /// アプリ強制終了後も resumePersistedSummaryQueueIfNeeded() で再開できるようにするため。
    /// didSet(非 actor-isolated context)から呼ぶため @MainActor を付けない。
    private func persistSummaryQueueSnapshot() {
        let snapshot = (currentlySummarizingStockId.map { [$0] } ?? []) + pendingSummaryStockIds
        UserDefaults.standard.set(snapshot, forKey: DefaultsKeys.stockSummaryQueue)
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
                if cancelledSummaryStockIds.remove(stockId) != nil {
                    // ユーザーが明示的にキャンセルした分は再投入しない
                    currentlySummarizingStockId = nil
                    return
                }
                // 翻訳優先 or ユーザーの一時停止により中断された。やり直せるようキュー先頭へ戻して終了する。
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
