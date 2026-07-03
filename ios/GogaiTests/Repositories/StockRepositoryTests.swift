import XCTest
@testable import Gogai

final class StockRepositoryTests: XCTestCase {
    var client: APIClient!
    var repository: StockRepository!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        repository = StockRepository(client: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeStock(id: Int = 1, categoryId: Int = 1, categoryName: String = "Tech") -> Stock {
        Stock(id: id, url: "https://example.com/\(id)", title: "Title \(id)", source: "Tech",
              category_id: categoryId, category_name: categoryName, summary: nil,
              has_translation: false, stocked_at: "2024-01-01T00:00:00Z", created_at: "2024-01-01T00:00:00Z")
    }

    func test_fetchAll_returnsStocks() async throws {
        let expected = [makeStock(id: 1), makeStock(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(expected)) }

        let stocks = try await repository.fetchAll()
        XCTAssertEqual(stocks.count, 2)
    }

    func test_fetchAll_withCategoryId_sendsQueryParam() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let categoryId = components.queryItems?.first(where: { $0.name == "category_id" })?.value
            XCTAssertEqual(categoryId, "5")
            return (200, try JSONEncoder().encode([Stock]()))
        }

        _ = try await repository.fetchAll(categoryId: 5)
    }

    func test_create_sendsBodyAndReturnsStock() async throws {
        let created = makeStock(id: 3)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/stocks") == true)
            return (201, try JSONEncoder().encode(created))
        }

        let stock = try await repository.create(url: "https://example.com/3", title: "Title 3", source: "Tech")
        XCTAssertEqual(stock.id, 3)
    }

    func test_update_sendsPutAndReturnsStock() async throws {
        let updated = makeStock(id: 1, categoryName: "あとで読む")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/stocks/1") == true)
            return (200, try JSONEncoder().encode(updated))
        }

        let stock = try await repository.update(id: 1, title: "A2", category: "あとで読む")
        XCTAssertEqual(stock.category_name, "あとで読む")
    }

    func test_delete_sendsDeleteRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/stocks/1") == true)
            return (204, Data())
        }

        try await repository.delete(id: 1)
    }

    func test_saveSummary_sendsPutWithSummary() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/stocks/1/summary") == true)
            return (204, Data())
        }

        try await repository.saveSummary(id: 1, summary: "要約")
    }

    func test_fetchTranslation_returnsPayload() async throws {
        let payload = StockTranslationPayload(segments: "{}", translated_at: "2024-01-01T00:00:00Z")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/api/stocks/1/translation") == true)
            return (200, try JSONEncoder().encode(payload))
        }

        let result = try await repository.fetchTranslation(id: 1)
        XCTAssertEqual(result.segments, "{}")
    }

    func test_fetchCategories_returnsCategories() async throws {
        let categories = [StockCategory(id: 1, name: "Tech", display_order: 0, created_at: "2024-01-01T00:00:00Z", stock_count: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(categories)) }

        let result = try await repository.fetchCategories()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Tech")
    }

    func test_reorderCategories_sendsPatchWithIds() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/stock-categories/reorder") == true)
            return (204, Data())
        }

        try await repository.reorderCategories(ids: [2, 1])
    }
}
