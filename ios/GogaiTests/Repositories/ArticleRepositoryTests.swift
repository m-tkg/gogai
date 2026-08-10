import XCTest
@testable import Gogai

final class ArticleRepositoryTests: XCTestCase {
    var client: APIClient!
    var repository: ArticleRepository!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        repository = ArticleRepository(client: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeArticle(id: Int = 1, isRead: Int = 0) -> Article {
        Article(id: id, feed_id: 1, guid: "guid-\(id)", title: "Title \(id)",
                link: "https://example.com/\(id)", summary: "Summary", content: nil,
                published_at: "2024-01-01T00:00:00Z", is_read: isRead,
                created_at: "2024-01-01T00:00:00Z", read_at: nil, liked_at: nil)
    }

    func test_fetchAll_returnsArticles() async throws {
        let articles = [makeArticle(id: 1), makeArticle(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }

        let result = try await repository.fetchAll()
        XCTAssertEqual(result.count, 2)
    }

    func test_fetchAll_withFeedId_includesQueryParam() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let feedId = components.queryItems?.first(where: { $0.name == "feedId" })?.value
            XCTAssertEqual(feedId, "3")
            return (200, Data("[]".utf8))
        }

        let _ = try await repository.fetchAll(feedId: 3)
    }

    func test_markAsRead_sendsPostRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/articles/5/read") == true)
            return (200, Data())
        }

        try await repository.markAsRead(id: 5)
    }

    func test_markAsUnread_sendsPostRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/articles/5/unread") == true)
            return (200, Data())
        }

        try await repository.markAsUnread(id: 5)
    }

    func test_like_sendsPostRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/articles/5/like") == true)
            return (200, Data())
        }

        try await repository.like(id: 5)
    }

    func test_unlike_sendsPostRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/articles/5/unlike") == true)
            return (200, Data())
        }

        try await repository.unlike(id: 5)
    }

    func test_fetchAll_likedフィルターはlikedOnlyクエリを送る() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "likedOnly" })?.value, "true")
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "unreadOnly" }))
            return (200, Data("[]".utf8))
        }

        _ = try await repository.fetchAll(filter: .liked)
    }

    func test_fetchAll_unreadフィルターはunreadOnlyクエリを送る() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "unreadOnly" })?.value, "true")
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "likedOnly" }))
            return (200, Data("[]".utf8))
        }

        _ = try await repository.fetchAll(filter: .unread)
    }

    func test_fetchAll_allフィルターは絞り込みクエリを送らない() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "unreadOnly" }))
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "likedOnly" }))
            return (200, Data("[]".utf8))
        }

        _ = try await repository.fetchAll(filter: .all)
    }
}
