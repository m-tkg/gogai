import Foundation

final class StockStore: ObservableObject {
    @Published var categories: [StockCategory] = []
    @Published var stocks: [Stock] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var sortAscending: Bool {
        didSet { UserDefaults.standard.set(sortAscending, forKey: DefaultsKeys.stockSortAscending) }
    }
    @Published private(set) var isGeneratingSummaries = false

    /// テスト用の差し替えポイント。デフォルトはオンデバイス Foundation Models(利用不可なら nil)。
    var makeSummaryGenerator: () -> (any TextGenerating)? = { LocalAI.makeGenerator() }

    private var client: (any APIClientProtocol)?
    /// 要約生成に失敗したストック ID(セッション内のみ。次回フォアグラウンドで再試行する)
    private var failedSummaryStockIds: Set<Int> = []

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

    /// summary が未生成のストックを stocked_at の古い順に逐次生成する。
    /// オンデバイス AI が利用できない端末や、既に実行中の場合は何もしない。
    @MainActor
    func generatePendingSummaries(session: URLSession = .shared) async {
        guard !isGeneratingSummaries, let generator = makeSummaryGenerator() else { return }
        let pending = stocks
            .filter { $0.summary == nil && !failedSummaryStockIds.contains($0.id) }
            .sorted { $0.stocked_at < $1.stocked_at }
        guard !pending.isEmpty else { return }

        isGeneratingSummaries = true
        defer { isGeneratingSummaries = false }

        let summarizer = StockSummarizer(generator: generator)
        for stock in pending {
            guard let url = URL(string: stock.url) else { continue }
            do {
                let summary = try await BackgroundExecution.run(name: "Stock.summarize") {
                    try await summarizer.summarize(url: url, title: stock.title, session: session)
                }
                try await saveSummary(id: stock.id, summary: summary)
            } catch {
                failedSummaryStockIds.insert(stock.id)
            }
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
