import Foundation

struct ArticleRepository: Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetchAll(feedId: Int? = nil, groupId: Int? = nil, filter: ArticleFilter = .all, sortOrder: ArticleSortOrder = .publishedAt, limit: Int = 1000, offset: Int = 0, includeSecret: Bool = false) async throws -> [Article] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sortBy", value: sortOrder.rawValue),
        ]
        if let feedId { queryItems.append(URLQueryItem(name: "feedId", value: String(feedId))) }
        if let groupId { queryItems.append(URLQueryItem(name: "groupId", value: String(groupId))) }
        switch filter {
        case .all: break
        case .unread: queryItems.append(URLQueryItem(name: "unreadOnly", value: "true"))
        // likedOnly 指定時はサーバーが sortBy を無視して liked_at 降順で返す
        case .liked: queryItems.append(URLQueryItem(name: "likedOnly", value: "true"))
        }
        if includeSecret { queryItems.append(URLQueryItem(name: "includeSecret", value: "true")) }
        return try await client.send(.get("/api/articles", queryItems: queryItems))
    }

    func fetchCounts() async throws -> [FeedCount] {
        try await client.send(.get("/api/articles/counts"))
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

    func like(id: Int) async throws {
        try await client.sendVoid(.post("/api/articles/\(id)/like"))
    }

    func unlike(id: Int) async throws {
        try await client.sendVoid(.post("/api/articles/\(id)/unlike"))
    }
}
