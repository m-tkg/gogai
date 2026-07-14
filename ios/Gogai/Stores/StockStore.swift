import Foundation

final class StockStore: ObservableObject, SummaryQueueDelegate {
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
    // 実体は SummaryQueue が保持する(状態変数・実行ロジック・レースコンディション回避のための
    // 手動同期はすべてそちら参照)。View(戻るボタン等)のライフサイクルに依存せず Store が
    // 持ち続けるため、画面遷移後もキュー処理を継続できる。ここでは SummaryQueue からの通知を
    // @Published プロパティへミラーし、UserDefaults への永続化を行う薄い consumer にする。

    /// 実行待ちのストック ID(先頭が次に実行される)
    @Published private(set) var pendingSummaryStockIds: [Int] = [] {
        didSet { persistSummaryQueueSnapshot() }
    }
    /// 現在生成中のストック ID
    @Published private(set) var currentlySummarizingStockId: Int? {
        didSet { persistSummaryQueueSnapshot() }
    }
    /// ストックIDごとの直近の要約失敗メッセージ
    @Published private(set) var summaryErrors: [Int: String] = [:] {
        didSet { persistSummaryErrorsSnapshot() }
    }
    /// ストックIDごとの要約生成ログ。生成中画面で直近の処理内容を表示する。
    @Published private(set) var summaryProgressLogs: [Int: [String]] = [:]
    /// ユーザーが一時停止ボタンで止めたかどうか(翻訳優先による一時停止とは別軸)
    @Published private(set) var isSummaryQueuePausedByUser = false

    private var summaryQueue: SummaryQueue!

    private let cache: AppCache
    private var client: (any APIClientProtocol)?

    init(cache: AppCache = .shared) {
        self.cache = cache
        self.sortAscending = UserDefaults.standard.bool(forKey: DefaultsKeys.stockSortAscending)
        // 起動時にキャッシュからカテゴリ・ストック一覧を読み込む
        self.categories = cache.loadStockCategories()
        self.stocks = cache.loadStocks()
        summaryQueue = SummaryQueue()
        summaryQueue.delegate = self
        summaryQueue.onChange = { [weak self] in
            self?.syncSummaryQueueState()
        }
    }

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    /// SummaryQueueDelegate: 実際の要約生成を行う。
    @MainActor
    func summaryQueue(_ queue: SummaryQueue, performSummaryFor stockId: Int, session: URLSession) async throws {
        try await generateSummary(for: stockId, session: session)
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
            cache.saveStockCategories(categories)
            cache.saveStocks(stocks)
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
        summaryErrors[id] = nil
        await removeEmptyCategoriesLocally()
    }

    @MainActor
    func saveSummary(id: Int, summary: String) async throws {
        guard let client else { return }
        try await StockRepository(client: client).saveSummary(id: id, summary: summary)
        if let idx = stocks.firstIndex(where: { $0.id == id }) {
            stocks[idx] = stocks[idx].updating(summary: .set(summary))
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
        guard let generator = makeSummaryGenerator() else { throw LocalAIError.aiUnavailable }
        guard let url = URL(string: stock.url) else { throw LocalAIError.invalidURL }

        resetSummaryProgressLog(for: stockId, firstMessage: "要約処理を開始")
        let providerLabel = LocalAI.activeProviderLabel
        let summarizer = StockSummarizer(generator: generator, providerLabel: providerLabel) { [weak self] message in
            self?.appendSummaryProgressLog(for: stockId, message: message)
        }
        try await BackgroundExecution.run(name: "Stock.summarize") {
            let summary = try await summarizer.summarize(url: url, title: stock.title, session: session)
            appendSummaryProgressLog(for: stockId, message: "生成した要約をサーバーへ保存中")
            try await saveSummary(id: stockId, summary: summary)
            appendSummaryProgressLog(for: stockId, message: "要約の保存が完了")
        }
    }

    /// 要約をキューに追加する(fire-and-forget)。View のライフサイクル(戻るボタン等)に
    /// 依存せず Store が保持し続けるため、画面遷移後もキュー処理を継続する。
    /// 既に生成中/待機中のストックは無視する。生成済みのストックは force: true のときだけ
    /// 再生成を受け付ける(呼び出し側で上書き確認を取ってから呼ぶこと)。
    @MainActor
    func requestSummary(for stockId: Int, force: Bool = false, session: URLSession = .shared) {
        guard force || stocks.first(where: { $0.id == stockId })?.summary == nil else { return }
        resetSummaryProgressLog(for: stockId, firstMessage: "要約キューに追加")
        summaryQueue.enqueue(stockId: stockId, session: session)
    }

    /// 翻訳を優先させるため、実行中の要約があれば中断してキュー処理を一時停止する。
    /// オンデバイス AI は同時に1リクエストしか処理できないための措置(#126 参照)。
    @MainActor
    func pauseSummaryQueueForTranslation() {
        summaryQueue.pauseForTranslation()
    }

    /// 翻訳完了後、要約キューを再開する。ユーザーが一時停止中の場合は再開しない。
    @MainActor
    func resumeSummaryQueueAfterTranslation(session: URLSession = .shared) {
        summaryQueue.resumeAfterTranslation(session: session)
    }

    /// ユーザー操作による一時停止。実行中の要約があれば中断し、キュー先頭へ戻す(やり直せるように)。
    /// 翻訳優先の一時停止とは独立して管理するため、翻訳が終わっても自動再開されない。
    @MainActor
    func pauseSummaryQueue() {
        summaryQueue.pauseByUser()
    }

    /// ユーザー操作による一時停止を解除する。翻訳優先の一時停止が別途かかっている場合は
    /// 再開されない(SummaryQueue 内部のガードによる)。
    @MainActor
    func resumeSummaryQueue(session: URLSession = .shared) {
        summaryQueue.resumeByUser(session: session)
    }

    /// キュー内の特定のストックをキャンセルする。待機中ならキューから外すだけ、
    /// 生成中なら中断し、一時停止と違い完了後もキューへ戻さない。
    @MainActor
    func cancelSummary(for stockId: Int) {
        summaryQueue.cancel(stockId: stockId)
    }

    /// エラーアラートを閉じた後の表示クリア用。
    @MainActor
    func clearSummaryError(for stockId: Int) {
        summaryQueue.clearError(for: stockId)
    }

    /// アプリ終了(強制終了含む)後の再起動時に、永続化された要約キューを再開する。
    /// fetchAll() で stocks を読み込んだ後に呼ぶこと。
    /// 既に要約済み/削除済みのストック ID は除外する(他端末で完了している場合があるため)。
    @MainActor
    func resumePersistedSummaryQueueIfNeeded(session: URLSession = .shared) {
        let persistedIds = UserDefaults.standard.array(forKey: DefaultsKeys.stockSummaryQueue) as? [Int] ?? []
        let restoredIds = persistedIds.filter { id in
            guard let stock = stocks.first(where: { $0.id == id }) else { return false }
            return stock.summary == nil
        }
        summaryQueue.restorePending(restoredIds, session: session)
    }

    /// アプリ再起動時に、永続化された要約エラー(赤いビックリマーク表示用)を復元する。
    /// fetchAll() で stocks を読み込んだ後に呼ぶこと。削除済み・他端末で要約成功済みのストックは除外する。
    @MainActor
    func restorePersistedSummaryErrorsIfNeeded() {
        guard let stored = UserDefaults.standard.dictionary(forKey: DefaultsKeys.stockSummaryErrors) as? [String: String] else { return }
        let restored = stored.reduce(into: [Int: String]()) { result, entry in
            guard let id = Int(entry.key),
                  let stock = stocks.first(where: { $0.id == id }),
                  stock.summary == nil
            else { return }
            result[id] = entry.value
        }
        summaryQueue.restoreErrors(restored)
    }

    /// 現在の要約キュー(生成中 + 待機中)を UserDefaults へ保存する。
    /// アプリ強制終了後も resumePersistedSummaryQueueIfNeeded() で再開できるようにするため。
    /// didSet(非 actor-isolated context)から呼ぶため @MainActor を付けない。
    private func persistSummaryQueueSnapshot() {
        let snapshot = (currentlySummarizingStockId.map { [$0] } ?? []) + pendingSummaryStockIds
        UserDefaults.standard.set(snapshot, forKey: DefaultsKeys.stockSummaryQueue)
    }

    /// summaryErrors(ストックIDごとの直近の要約失敗メッセージ)を UserDefaults へ保存する。
    /// アプリ再起動後もカテゴリ一覧・ストック一覧の赤いビックリマーク表示を維持するため
    /// (複数端末間の同期はしない。要約生成自体が端末ローカルのオンデバイス AI 処理のため)。
    /// didSet(非 actor-isolated context)から呼ぶため @MainActor を付けない。
    private func persistSummaryErrorsSnapshot() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: summaryErrors.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyed, forKey: DefaultsKeys.stockSummaryErrors)
    }

    /// SummaryQueue の状態を @Published プロパティへミラーする(onChange から呼ばれる)。
    /// onChange クロージャは(persistSummaryQueueSnapshot 等と同様に)非 actor-isolated
    /// コンテキストから呼ばれるため @MainActor を付けない。
    private func syncSummaryQueueState() {
        pendingSummaryStockIds = summaryQueue.pending
        currentlySummarizingStockId = summaryQueue.currentlySummarizing
        summaryErrors = summaryQueue.errors
        isSummaryQueuePausedByUser = summaryQueue.isPausedByUser
    }

    @MainActor
    private func resetSummaryProgressLog(for stockId: Int, firstMessage: String) {
        summaryProgressLogs[stockId] = [firstMessage]
    }

    @MainActor
    private func appendSummaryProgressLog(for stockId: Int, message: String) {
        var logs = summaryProgressLogs[stockId] ?? []
        logs.append(message)
        summaryProgressLogs[stockId] = Array(logs.suffix(50))
    }

    @MainActor
    func reorderCategories(from source: IndexSet, to destination: Int) async throws {
        guard let client else { return }
        categories = try await reorderAndPersist(categories, from: source, to: destination) { ids in
            try await StockRepository(client: client).reorderCategories(ids: ids)
        }
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
