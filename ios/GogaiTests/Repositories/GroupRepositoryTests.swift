import XCTest
@testable import Gogai

final class GroupRepositoryTests: XCTestCase {
    var client: APIClient!
    var repository: GroupRepository!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        repository = GroupRepository(client: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_fetchAll_returnsGroups() async throws {
        let expected = [
            Group(id: 1, name: "Tech", is_secret: 0, created_at: "2024-01-01T00:00:00Z", display_order: 0),
            Group(id: 2, name: "News", is_secret: 0, created_at: "2024-01-02T00:00:00Z", display_order: 0),
        ]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(expected)) }

        let groups = try await repository.fetchAll()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].name, "Tech")
        XCTAssertEqual(groups[1].name, "News")
    }

    func test_create_sendsNameAndReturnsGroup() async throws {
        let created = Group(id: 3, name: "Sports", is_secret: 0, created_at: "2024-01-03T00:00:00Z", display_order: 0)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, try JSONEncoder().encode(created))
        }

        let group = try await repository.create(name: "Sports")
        XCTAssertEqual(group.id, 3)
        XCTAssertEqual(group.name, "Sports")
    }

    func test_update_sendsNameAndReturnsUpdatedGroup() async throws {
        let updated = Group(id: 1, name: "Technology", is_secret: 0, created_at: "2024-01-01T00:00:00Z", display_order: 0)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/groups/1") == true)
            return (200, try JSONEncoder().encode(updated))
        }

        let group = try await repository.update(id: 1, name: "Technology")
        XCTAssertEqual(group.name, "Technology")
    }

    func test_update_withIsSecret_returnsGroupWithIsSecret() async throws {
        let updated = Group(id: 1, name: "Secret Group", is_secret: 1, created_at: "2024-01-01T00:00:00Z", display_order: 0)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            return (200, try JSONEncoder().encode(updated))
        }

        let group = try await repository.update(id: 1, name: "Secret Group", isSecret: 1)
        XCTAssertEqual(group.is_secret, 1)
    }

    func test_delete_sendsDeleteRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/groups/1") == true)
            return (200, Data())
        }

        try await repository.delete(id: 1)
    }
}
