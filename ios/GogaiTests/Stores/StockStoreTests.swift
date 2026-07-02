import XCTest
@testable import Gogai

final class StockStoreTests: XCTestCase {
    var client: APIClient!
    var store: StockStore!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        store = StockStore()
        store.configure(with: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.stockSortAscending)
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
    func test_createStock_appendsToStocks() async {
        let created = makeStock(id: 5)
        MockURLProtocol.requestHandler = { _ in (201, try JSONEncoder().encode(created)) }

        let result = await store.createStock(url: "https://example.com/5", source: "Tech")

        XCTAssertEqual(result?.id, 5)
        XCTAssertEqual(store.stocks.count, 1)
    }

    @MainActor
    func test_createStock_duplicateUrl_updatesExistingRatherThanAppending() async {
        store.stocks = [makeStock(id: 1)]
        let existing = makeStock(id: 1)
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(existing)) }

        _ = await store.createStock(url: "https://example.com/1", source: "Tech")

        XCTAssertEqual(store.stocks.count, 1)
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

    // MARK: - sortAscending の永続化

    func test_sortAscending_defaultsToFalse() {
        XCTAssertFalse(store.sortAscending)
    }

    @MainActor
    func test_sortAscending_persistsToUserDefaults() {
        store.sortAscending = true

        XCTAssertTrue(UserDefaults.standard.bool(forKey: DefaultsKeys.stockSortAscending))
    }
}
