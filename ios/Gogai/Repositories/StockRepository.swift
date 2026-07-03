import Foundation

struct StockRepository: Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetchAll(categoryId: Int? = nil) async throws -> [Stock] {
        var queryItems: [URLQueryItem]?
        if let categoryId {
            queryItems = [URLQueryItem(name: "category_id", value: String(categoryId))]
        }
        return try await client.send(.get("/api/stocks", queryItems: queryItems))
    }

    func create(url: String, title: String? = nil, source: String? = nil, category: String? = nil) async throws -> Stock {
        struct Body: Encodable, Sendable {
            let url: String
            let title: String?
            let source: String?
            let category: String?
        }
        return try await client.send(try .post("/api/stocks", body: Body(url: url, title: title, source: source, category: category)))
    }

    func update(id: Int, title: String, category: String) async throws -> Stock {
        struct Body: Encodable, Sendable {
            let title: String
            let category: String
        }
        return try await client.send(try .put("/api/stocks/\(id)", body: Body(title: title, category: category)))
    }

    func delete(id: Int) async throws {
        try await client.sendVoid(.delete("/api/stocks/\(id)"))
    }

    func saveSummary(id: Int, summary: String) async throws {
        struct Body: Encodable, Sendable { let summary: String }
        try await client.sendVoid(try .put("/api/stocks/\(id)/summary", body: Body(summary: summary)))
    }

    func fetchTranslation(id: Int) async throws -> StockTranslationPayload {
        try await client.send(.get("/api/stocks/\(id)/translation"))
    }

    func saveTranslation(id: Int, segments: String) async throws {
        struct Body: Encodable, Sendable { let segments: String }
        try await client.sendVoid(try .put("/api/stocks/\(id)/translation", body: Body(segments: segments)))
    }

    func fetchCategories() async throws -> [StockCategory] {
        try await client.send(.get("/api/stock-categories"))
    }

    func reorderCategories(ids: [Int]) async throws {
        struct Body: Encodable, Sendable { let ids: [Int] }
        try await client.sendVoid(try .patch("/api/stock-categories/reorder", body: Body(ids: ids)))
    }
}
