import XCTest
@testable import Gogai

final class AppCacheTests: XCTestCase {
    var tmpDir: URL!
    var cache: AppCache!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        cache = AppCache(directory: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeArticle(id: Int = 1) -> Article {
        Article(id: id, feed_id: 1, guid: "guid-\(id)", title: "Title \(id)",
                link: nil, summary: nil, content: nil, published_at: nil,
                is_read: 0, is_favorite: 0, created_at: "2024-01-01T00:00:00Z",
                read_at: nil)
    }

    private func makeFeed(id: Int = 1) -> Feed {
        Feed(id: id, url: "https://example.com/feed.xml", title: "Feed \(id)",
             favicon_url: nil, group_id: nil, last_fetched_at: nil,
             created_at: "2024-01-01T00:00:00Z", display_order: 0)
    }

    private func makeGroup(id: Int = 1) -> Group {
        Group(id: id, name: "Group \(id)", is_secret: 0,
              created_at: "2024-01-01T00:00:00Z", display_order: 0)
    }

    // MARK: - Articles

    func test_loadAllArticles_returnsEmpty_whenNoCache() {
        XCTAssertTrue(cache.loadAllArticles().isEmpty)
    }

    func test_saveAndLoad_articles() {
        let articles = [makeArticle(id: 1), makeArticle(id: 2)]
        cache.saveAllArticles(articles)

        let loaded = cache.loadAllArticles()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, 1)
        XCTAssertEqual(loaded[1].id, 2)
    }

    func test_saveAllArticles_overwritesPreviousData() {
        cache.saveAllArticles([makeArticle(id: 1), makeArticle(id: 2)])
        cache.saveAllArticles([makeArticle(id: 3)])

        let loaded = cache.loadAllArticles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, 3)
    }

    // MARK: - Feeds

    func test_loadFeeds_returnsEmpty_whenNoCache() {
        XCTAssertTrue(cache.loadFeeds().isEmpty)
    }

    func test_saveAndLoad_feeds() {
        let feeds = [makeFeed(id: 1), makeFeed(id: 2)]
        cache.saveFeeds(feeds)

        let loaded = cache.loadFeeds()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, 1)
        XCTAssertEqual(loaded[1].id, 2)
    }

    // MARK: - Groups

    func test_loadGroups_returnsEmpty_whenNoCache() {
        XCTAssertTrue(cache.loadGroups().isEmpty)
    }

    func test_saveAndLoad_groups() {
        let groups = [makeGroup(id: 1), makeGroup(id: 2)]
        cache.saveGroups(groups)

        let loaded = cache.loadGroups()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, 1)
        XCTAssertEqual(loaded[1].id, 2)
    }

    // MARK: - FeedCounts

    func test_loadFeedCounts_returnsEmpty_whenNoCache() {
        XCTAssertTrue(cache.loadFeedCounts().isEmpty)
    }

    func test_saveAndLoad_feedCounts() {
        let counts = [
            FeedCount(feed_id: 1, total: 3, unread: 2, favorite: 1),
            FeedCount(feed_id: 2, total: 5, unread: 0, favorite: 0),
        ]
        cache.saveFeedCounts(counts)

        let loaded = cache.loadFeedCounts()
        XCTAssertEqual(loaded, counts)
    }

    // MARK: - clearAll

    func test_clearAll_removesAllCachedData() {
        cache.saveAllArticles([makeArticle(id: 1)])
        cache.saveFeeds([makeFeed(id: 1)])
        cache.saveGroups([makeGroup(id: 1)])

        cache.clearAll()

        XCTAssertTrue(cache.loadAllArticles().isEmpty)
        XCTAssertTrue(cache.loadFeeds().isEmpty)
        XCTAssertTrue(cache.loadGroups().isEmpty)
    }

    func test_clearAll_allowsSavingAgainAfterwards() {
        cache.saveAllArticles([makeArticle(id: 1)])
        cache.clearAll()
        cache.saveAllArticles([makeArticle(id: 2)])

        let loaded = cache.loadAllArticles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, 2)
    }
}
