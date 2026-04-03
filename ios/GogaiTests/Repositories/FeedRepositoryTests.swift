import XCTest
@testable import Gogai

final class FeedRepositoryTests: XCTestCase {
    var client: APIClient!
    var repository: FeedRepository!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        repository = FeedRepository(client: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeFeed(id: Int = 1, groupId: Int? = nil) -> Feed {
        Feed(id: id, url: "https://example.com/feed.xml", title: "Example",
             favicon_url: nil, group_id: groupId, last_fetched_at: nil, created_at: "2024-01-01T00:00:00Z", display_order: 0)
    }

    func test_fetchAll_returnsFeeds() async throws {
        let feeds = [makeFeed(id: 1), makeFeed(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feeds)) }

        let result = try await repository.fetchAll()
        XCTAssertEqual(result.count, 2)
    }

    func test_create_withGroupId_includesGroupId() async throws {
        let newFeed = makeFeed(id: 5, groupId: 3)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["groupId"] as? Int, 3)
            return (200, try JSONEncoder().encode(newFeed))
        }

        let feed = try await repository.create(url: "https://example.com/feed.xml", groupId: 3)
        XCTAssertEqual(feed.group_id, 3)
    }

    func test_delete_sendsDeleteRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/feeds/7") == true)
            return (200, Data())
        }

        try await repository.delete(id: 7)
    }

    func test_refreshAll_returnsRefreshResult() async throws {
        let result = RefreshResult(refreshed: 5, failed: 1)
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(result)) }

        let refreshResult = try await repository.refreshAll()
        XCTAssertEqual(refreshResult.refreshed, 5)
        XCTAssertEqual(refreshResult.failed, 1)
    }
}
