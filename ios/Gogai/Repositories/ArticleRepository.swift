import Foundation

struct ArticleRepository: Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetchAll(feedId: Int? = nil, groupId: Int? = nil, unreadOnly: Bool = false, sortOrder: ArticleSortOrder = .publishedAt, limit: Int = 100, offset: Int = 0) async throws -> [Article] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sortBy", value: sortOrder.rawValue),
        ]
        if let feedId { queryItems.append(URLQueryItem(name: "feedId", value: String(feedId))) }
        if let groupId { queryItems.append(URLQueryItem(name: "groupId", value: String(groupId))) }
        if unreadOnly { queryItems.append(URLQueryItem(name: "unreadOnly", value: "true")) }
        return try await client.send(.get("/api/articles", queryItems: queryItems))
    }

    func fetch(id: Int) async throws -> Article {
        try await client.send(.get("/api/articles/\(id)"))
    }

    func markAsRead(id: Int) async throws {
        try await client.sendVoid(.post("/api/articles/\(id)/read"))
    }

    func markAsUnread(id: Int) async throws {
        try await client.sendVoid(.post("/api/articles/\(id)/unread"))
    }

    struct AIResult: Codable, Sendable {
        let output: String
        let cached: Bool
    }

    func runAI(id: Int, action: AIAction, force: Bool = false) async throws -> AIResult {
        struct Body: Encodable, Sendable {
            let action: String
            let force: Bool
        }
        return try await client.send(try .post("/api/articles/\(id)/claude", body: Body(action: action.rawValue, force: force)))
    }

    enum AIAction: String, Sendable {
        case summarize
        case translate
    }
}
