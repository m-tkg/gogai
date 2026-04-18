import XCTest
@testable import Gogai

final class APIClientTests: XCTestCase {
    var client: APIClient!
    let baseURL = URL(string: "http://localhost:3040")!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: baseURL, session: .mock())
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Successful requests

    func test_send_get_decodesResponse() async throws {
        let expected = [Group(id: 1, name: "Tech", is_secret: 0, created_at: "2024-01-01T00:00:00Z", display_order: 0)]
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/groups") == true)
            let data = try JSONEncoder().encode(expected)
            return (200, data)
        }

        let groups: [Group] = try await client.send(.get("/api/groups"))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "Tech")
    }

    func test_send_post_withBody_sendsCorrectRequest() async throws {
        struct Body: Codable { let name: String }
        let responseGroup = Group(id: 2, name: "News", is_secret: 0, created_at: "2024-01-01T00:00:00Z", display_order: 0)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONDecoder().decode(Body.self, from: request.httpBody!)
            XCTAssertEqual(body.name, "News")
            return (200, try JSONEncoder().encode(responseGroup))
        }

        let group: Group = try await client.send(try .post("/api/groups", body: Body(name: "News")))
        XCTAssertEqual(group.id, 2)
    }

    func test_sendVoid_success() async throws {
        MockURLProtocol.requestHandler = { _ in (200, Data()) }
        try await client.sendVoid(.post("/api/articles/1/read"))
    }

    // MARK: - Error cases

    func test_send_httpError_throwsHTTPError() async throws {
        MockURLProtocol.requestHandler = { _ in
            (404, Data("{\"error\":\"not found\"}".utf8))
        }

        do {
            let _: Group = try await client.send(.get("/api/groups/999"))
            XCTFail("Expected error")
        } catch let error as APIError {
            if case .httpError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        }
    }

    func test_send_urlError_isPropagatedAsURLError() async throws {
        // ネットワーク障害は URLError をそのまま投げ直すこと（APIError に包まない）。
        // ArticleStore 側で `catch is URLError` 判定して再送キュー制御するため。
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }

        do {
            try await client.sendVoid(.post("/api/articles/1/read"))
            XCTFail("Expected error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotConnectToHost)
        } catch {
            XCTFail("Expected URLError, got \(type(of: error)): \(error)")
        }
    }

    func test_send_invalidJSON_throwsDecodingError() async throws {
        MockURLProtocol.requestHandler = { _ in (200, Data("not json".utf8)) }

        do {
            let _: Group = try await client.send(.get("/api/groups/1"))
            XCTFail("Expected error")
        } catch let error as APIError {
            if case .decodingError = error {
                // expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        }
    }

    // MARK: - Endpoint URL building

    func test_endpoint_queryItems_appendedToURL() async throws {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let feedId = components.queryItems?.first(where: { $0.name == "feedId" })?.value
            XCTAssertEqual(feedId, "5")
            return (200, Data("[]".utf8))
        }

        let _: [Article] = try await client.send(.get("/api/articles", queryItems: [
            URLQueryItem(name: "feedId", value: "5")
        ]))
    }
}
