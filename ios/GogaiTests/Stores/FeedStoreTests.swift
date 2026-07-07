import XCTest
@testable import Gogai

final class FeedStoreTests: StoreTestCase {
    var store: FeedStore!

    override func setUp() {
        super.setUp()
        store = FeedStore()
        store.configure(with: client)
    }

    private func makeFeed(id: Int = 1, groupId: Int? = nil, displayOrder: Int = 0) -> Feed {
        Feed(id: id, url: "https://example.com/feed.xml", title: "Example \(id)",
             favicon_url: nil, group_id: groupId, last_fetched_at: nil, created_at: "2024-01-01T00:00:00Z",
             display_order: displayOrder)
    }

    @MainActor
    func test_fetchFeeds_updatesFeeds() async {
        let expected = [makeFeed(id: 1), makeFeed(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(expected)) }

        await store.fetchFeeds()

        XCTAssertEqual(store.feeds.count, 2)
    }

    func test_feedsForGroup_filtersCorrectly() {
        store.feeds = [makeFeed(id: 1, groupId: 1), makeFeed(id: 2, groupId: 2), makeFeed(id: 3, groupId: 1)]

        let filtered = store.feeds(for: 1)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.group_id == 1 })
    }

    func test_feedsForGroup_nil_returnsAll() {
        store.feeds = [makeFeed(id: 1, groupId: 1), makeFeed(id: 2, groupId: nil)]

        let all = store.feeds(for: nil)
        XCTAssertEqual(all.count, 2)
    }

    @MainActor
    func test_deleteFeed_removesFromFeeds() async throws {
        store.feeds = [makeFeed(id: 1), makeFeed(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        try await store.deleteFeed(id: 1)

        XCTAssertEqual(store.feeds.count, 1)
        XCTAssertEqual(store.feeds[0].id, 2)
    }

    @MainActor
    func test_refreshAll_callsOnRefreshComplete() async throws {
        var completionCalled = false
        store.configure(with: client, onRefreshComplete: { completionCalled = true })
        let result = RefreshResult(refreshed: 3, failed: 0)
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(result)) }

        _ = try await store.refreshAll()

        XCTAssertTrue(completionCalled)
    }

    // MARK: - reorderFeeds

    @MainActor
    func test_reorderFeeds_updatesLocalOrder() async throws {
        store.feeds = [makeFeed(id: 1, groupId: 1, displayOrder: 0),
                       makeFeed(id: 2, groupId: 1, displayOrder: 1),
                       makeFeed(id: 3, groupId: 1, displayOrder: 2)]
        MockURLProtocol.requestHandler = { _ in (204, Data()) }

        try await store.reorderFeeds(from: IndexSet(integer: 0), to: 3, groupId: 1)

        let groupFeeds = store.feeds(for: 1)
        XCTAssertEqual(groupFeeds[0].id, 2)
        XCTAssertEqual(groupFeeds[1].id, 3)
        XCTAssertEqual(groupFeeds[2].id, 1)
    }

    // MARK: - isRefreshing

    @MainActor
    func test_isRefreshing_defaultsToFalse() {
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    func test_isRefreshing_falseAfterRefreshAllCompletes() async throws {
        let result = RefreshResult(refreshed: 1, failed: 0)
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(result)) }

        _ = try await store.refreshAll()

        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    func test_isRefreshing_falseAfterRefreshAllFails() async {
        MockURLProtocol.requestHandler = { _ in (500, Data()) }

        _ = try? await store.refreshAll()

        XCTAssertFalse(store.isRefreshing)
    }

    // MARK: - キャッシュ

    private func makeTmpCache() -> (AppCache, URL) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return (AppCache(directory: tmpDir), tmpDir)
    }

    func test_init_loadsFeedsFromCache() {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cachedFeeds = [makeFeed(id: 42)]
        testCache.saveFeeds(cachedFeeds)

        let storeWithCache = FeedStore(cache: testCache)

        XCTAssertEqual(storeWithCache.feeds.count, 1, "起動時にキャッシュからフィードを読み込むこと")
        XCTAssertEqual(storeWithCache.feeds[0].id, 42)
    }

    @MainActor
    func test_fetchFeeds_savesToCache() async {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let storeWithCache = FeedStore(cache: testCache)
        storeWithCache.configure(with: client)

        let feeds = [makeFeed(id: 1), makeFeed(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feeds)) }

        await storeWithCache.fetchFeeds()

        let cached = testCache.loadFeeds()
        XCTAssertEqual(cached.count, 2, "fetchFeeds 後にキャッシュが保存されること")
    }
}
