import XCTest
@testable import Gogai

final class GroupStoreTests: XCTestCase {
    var client: APIClient!
    var store: GroupStore!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        store = GroupStore()
        store.configure(with: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeGroup(id: Int = 1, name: String = "Tech", isSecret: Int = 0) -> Group {
        Group(id: id, name: name, is_secret: isSecret, created_at: "2024-01-01T00:00:00Z")
    }

    @MainActor
    func test_fetchGroups_updatesGroups() async {
        let expected = [makeGroup(id: 1, name: "Tech"), makeGroup(id: 2, name: "News")]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(expected)) }

        await store.fetchGroups()

        XCTAssertEqual(store.groups.count, 2)
        XCTAssertEqual(store.groups[0].name, "Tech")
        XCTAssertNil(store.error)
    }

    @MainActor
    func test_fetchGroups_setsError_onFailure() async {
        MockURLProtocol.requestHandler = { _ in (500, Data()) }

        await store.fetchGroups()

        XCTAssertNotNil(store.error)
    }

    @MainActor
    func test_createGroup_appendsToGroups() async throws {
        store.groups.removeAll()
        let newGroup = makeGroup(id: 5, name: "Sports")
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(newGroup)) }

        try await store.createGroup(name: "Sports")

        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].name, "Sports")
    }

    @MainActor
    func test_deleteGroup_removesFromGroups() async throws {
        store.groups = [makeGroup(id: 1), makeGroup(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        try await store.deleteGroup(id: 1)

        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].id, 2)
    }

    @MainActor
    func test_updateGroup_replacesInGroups() async throws {
        store.groups = [makeGroup(id: 1, name: "Old")]
        let updated = makeGroup(id: 1, name: "New")
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(updated)) }

        try await store.updateGroup(id: 1, name: "New")

        XCTAssertEqual(store.groups[0].name, "New")
    }

    // MARK: - showSecretGroups / visibleGroups

    @MainActor
    func test_visibleGroups_hidesSecretGroups_whenShowSecretGroupsIsFalse() {
        store.groups = [makeGroup(id: 1, name: "Public"), makeGroup(id: 2, name: "Secret", isSecret: 1)]
        store.showSecretGroups = false

        XCTAssertEqual(store.visibleGroups.count, 1)
        XCTAssertEqual(store.visibleGroups[0].name, "Public")
    }

    @MainActor
    func test_visibleGroups_showsSecretGroups_whenShowSecretGroupsIsTrue() {
        store.groups = [makeGroup(id: 1, name: "Public"), makeGroup(id: 2, name: "Secret", isSecret: 1)]
        store.showSecretGroups = true

        XCTAssertEqual(store.visibleGroups.count, 2)
    }

    @MainActor
    func test_showSecretGroups_defaultsToFalse() {
        XCTAssertFalse(store.showSecretGroups)
    }
}
