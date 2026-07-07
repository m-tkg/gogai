import XCTest
@testable import Gogai

final class GroupStoreTests: StoreTestCase {
    var store: GroupStore!

    override func setUp() {
        super.setUp()
        store = GroupStore()
        store.configure(with: client)
    }

    private func makeGroup(id: Int = 1, name: String = "Tech", isSecret: Int = 0, displayOrder: Int = 0) -> Group {
        Group(id: id, name: name, is_secret: isSecret, created_at: "2024-01-01T00:00:00Z", display_order: displayOrder)
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

    // MARK: - expandedGroupIds / isExpanded / toggleExpanded

    @MainActor
    func test_isExpanded_defaultsToTrue() {
        XCTAssertTrue(store.isExpanded(id: 1))
        XCTAssertTrue(store.isExpanded(id: 99))
    }

    @MainActor
    func test_toggleExpanded_collapsesExpandedGroup() {
        store.toggleExpanded(id: 1)

        XCTAssertFalse(store.isExpanded(id: 1))
    }

    @MainActor
    func test_toggleExpanded_expandsCollapsedGroup() {
        store.toggleExpanded(id: 1)
        store.toggleExpanded(id: 1)

        XCTAssertTrue(store.isExpanded(id: 1))
    }

    @MainActor
    func test_toggleExpanded_doesNotAffectOtherGroups() {
        store.toggleExpanded(id: 1)

        XCTAssertFalse(store.isExpanded(id: 1))
        XCTAssertTrue(store.isExpanded(id: 2))
    }

    @MainActor
    func test_deleteGroup_clearsCollapsedState() async throws {
        store.groups = [makeGroup(id: 1)]
        store.toggleExpanded(id: 1)
        XCTAssertFalse(store.isExpanded(id: 1))

        MockURLProtocol.requestHandler = { _ in (200, Data()) }
        try await store.deleteGroup(id: 1)

        XCTAssertTrue(store.isExpanded(id: 1))
    }

    // MARK: - reorderGroups

    @MainActor
    func test_reorderGroups_updatesLocalOrder() async throws {
        store.groups = [makeGroup(id: 1, name: "A", displayOrder: 0),
                        makeGroup(id: 2, name: "B", displayOrder: 1),
                        makeGroup(id: 3, name: "C", displayOrder: 2)]
        MockURLProtocol.requestHandler = { _ in (204, Data()) }

        try await store.reorderGroups(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(store.groups[0].id, 2)
        XCTAssertEqual(store.groups[1].id, 3)
        XCTAssertEqual(store.groups[2].id, 1)
    }

    // MARK: - キャッシュ

    private func makeTmpCache() -> (AppCache, URL) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return (AppCache(directory: tmpDir), tmpDir)
    }

    func test_init_loadsGroupsFromCache() {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cachedGroups = [makeGroup(id: 42, name: "Cached Group")]
        testCache.saveGroups(cachedGroups)

        let storeWithCache = GroupStore(cache: testCache)

        XCTAssertEqual(storeWithCache.groups.count, 1, "起動時にキャッシュからグループを読み込むこと")
        XCTAssertEqual(storeWithCache.groups[0].id, 42)
    }

    @MainActor
    func test_fetchGroups_savesToCache() async {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let storeWithCache = GroupStore(cache: testCache)
        storeWithCache.configure(with: client)

        let groups = [makeGroup(id: 1), makeGroup(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(groups)) }

        await storeWithCache.fetchGroups()

        let cached = testCache.loadGroups()
        XCTAssertEqual(cached.count, 2, "fetchGroups 後にキャッシュが保存されること")
    }

    // MARK: - secretFeedIds(in:)

    private func makeFeed(id: Int, groupId: Int?) -> Feed {
        Feed(id: id, url: "https://example.com/\(id)", title: "Feed \(id)",
             favicon_url: nil, group_id: groupId, last_fetched_at: nil,
             created_at: "2024-01-01T00:00:00Z", display_order: 0)
    }

    func test_secretFeedIds_シークレットグループ所属のフィードIDを返す() {
        store.groups = [makeGroup(id: 1, isSecret: 0), makeGroup(id: 2, isSecret: 1)]
        let feeds = [
            makeFeed(id: 10, groupId: 1),   // 通常グループ
            makeFeed(id: 11, groupId: 2),   // シークレット
            makeFeed(id: 12, groupId: nil), // 未分類
        ]
        XCTAssertEqual(store.secretFeedIds(in: feeds), [11])
    }

    func test_secretFeedIds_showSecretGroups中は空集合を返す() {
        store.groups = [makeGroup(id: 2, isSecret: 1)]
        store.showSecretGroups = true
        let feeds = [makeFeed(id: 11, groupId: 2)]
        XCTAssertEqual(store.secretFeedIds(in: feeds), [])
    }

    func test_secretFeedIds_シークレットグループがなければ空集合() {
        store.groups = [makeGroup(id: 1, isSecret: 0)]
        let feeds = [makeFeed(id: 10, groupId: 1)]
        XCTAssertEqual(store.secretFeedIds(in: feeds), [])
    }
}
