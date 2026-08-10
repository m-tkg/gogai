import XCTest
@testable import Gogai

final class FeedCountTests: XCTestCase {
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

    func test_fetchCounts_GETでcountsを呼びデコードする() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/api/articles/counts") == true)
            let json = """
            [{"feed_id":1,"total":3,"unread":2,"liked":1},
             {"feed_id":2,"total":5,"unread":0,"liked":0}]
            """
            return (200, Data(json.utf8))
        }

        let counts = try await repository.fetchCounts()
        XCTAssertEqual(counts.count, 2)
        XCTAssertEqual(counts[0].feed_id, 1)
        XCTAssertEqual(counts[0].unread, 2)
        XCTAssertEqual(counts[0].liked, 1)
        XCTAssertEqual(counts[1].total, 5)
        XCTAssertEqual(counts[1].liked, 0)
    }
}
