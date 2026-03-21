import XCTest
@testable import Gogai

final class ArticleStoreTests: XCTestCase {
    var client: APIClient!
    var store: ArticleStore!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        store = ArticleStore()
        store.configure(with: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeArticle(id: Int = 1, feedId: Int = 1, isRead: Int = 0) -> Article {
        Article(id: id, feed_id: feedId, guid: "guid-\(id)", title: "Title \(id)",
                link: nil, summary: nil, content: nil, published_at: nil,
                is_read: isRead, created_at: "2024-01-01T00:00:00Z",
                ai_summary: nil, ai_translation: nil, read_at: nil)
    }

    @MainActor
    func test_fetchArticles_updatesArticles() async {
        let expected = [makeArticle(id: 1), makeArticle(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(expected)) }

        await store.fetchArticles()

        XCTAssertEqual(store.articles.count, 2)
        XCTAssertNil(store.error)
    }

    @MainActor
    func test_markAsRead_optimisticallyUpdates() async {
        store.articles = [makeArticle(id: 1, isRead: 0)]
        var requestReceived = false
        MockURLProtocol.requestHandler = { _ in
            requestReceived = true
            return (200, Data())
        }

        await store.markAsRead(id: 1)

        XCTAssertTrue(requestReceived)
        XCTAssertTrue(store.articles[0].isRead)
    }

    @MainActor
    func test_markAsRead_rollsBackOnFailure() async {
        store.articles = [makeArticle(id: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (500, Data()) }

        await store.markAsRead(id: 1)

        XCTAssertFalse(store.articles[0].isRead)
        XCTAssertNotNil(store.error)
    }

    @MainActor
    func test_markAsUnread_optimisticallyUpdates() async {
        store.articles = [makeArticle(id: 1, isRead: 1)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.markAsUnread(id: 1)

        XCTAssertFalse(store.articles[0].isRead)
    }

    func test_unreadCount_returnsCorrectCount() {
        store.articles = [
            makeArticle(id: 1, isRead: 0),
            makeArticle(id: 2, isRead: 1),
            makeArticle(id: 3, isRead: 0),
        ]

        XCTAssertEqual(store.unreadCount(for: nil), 2)
    }

    // MARK: - unreadCount(forGroupFeedIds:)

    func test_unreadCount_forGroupFeedIds_returnsUnreadCountForSpecifiedFeeds() {
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
            makeArticle(id: 2, feedId: 10, isRead: 1),
            makeArticle(id: 3, feedId: 20, isRead: 0),
            makeArticle(id: 4, feedId: 30, isRead: 0),
        ]

        XCTAssertEqual(store.unreadCount(forGroupFeedIds: [10, 20]), 2)
    }

    func test_unreadCount_forGroupFeedIds_excludesFeedsNotInGroup() {
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
            makeArticle(id: 2, feedId: 20, isRead: 0),
        ]

        XCTAssertEqual(store.unreadCount(forGroupFeedIds: [10]), 1)
    }

    func test_unreadCount_forGroupFeedIds_returnsZeroForEmptyFeedIds() {
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
        ]

        XCTAssertEqual(store.unreadCount(forGroupFeedIds: []), 0)
    }

    func test_unreadCount_forGroupFeedIds_fallsBackToArticles_whenAllArticlesEmpty() {
        store.articles = [makeArticle(id: 1, feedId: 10, isRead: 0)]
        // allArticles が空の場合は articles を使う
        XCTAssertEqual(store.unreadCount(forGroupFeedIds: [10]), 1)
    }

    @MainActor
    func test_unreadCount_forGroupFeedIds_usesAllArticles_whenAllArticlesPopulated() async {
        // fetchArticles で allArticles を feed_id=10 の記事で埋める
        let feed10Articles = [makeArticle(id: 1, feedId: 10, isRead: 0), makeArticle(id: 2, feedId: 10, isRead: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feed10Articles)) }
        await store.fetchArticles(feedId: 10)

        // articles は feed_id=10 のみ、allArticles も feed_id=10 が入っている
        // articles を feed_id=20 で上書き（allArticles は更新されない）
        store.articles = [makeArticle(id: 3, feedId: 20, isRead: 0)]

        // allArticles（feed_id=10 の未読1件）を使う
        XCTAssertEqual(store.unreadCount(forGroupFeedIds: [10]), 1)
    }

    // MARK: - refresh() + unreadOnly 既読記事保持

    @MainActor
    func test_refresh_preservesCurrentlyReadArticle_whenUnreadOnly() async {
        // unreadOnly: true の状態で記事を2件表示（id:1 が既読、id:2 が未読）
        store.unreadOnly = true
        store.articles = [makeArticle(id: 1, isRead: 1), makeArticle(id: 2, isRead: 0)]
        // サーバーは未読のみ返す（id:1 は返さない）
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 2, isRead: 0)]))
        }

        await store.refresh()

        // id:1（既読）は引き続きリストに残っていること
        XCTAssertTrue(store.articles.contains { $0.id == 1 }, "既読記事がリストから消えてはいけない")
        XCTAssertTrue(store.articles.contains { $0.id == 2 }, "未読記事は引き続き表示される")
    }

    @MainActor
    func test_refresh_doesNotPreserveReadArticle_whenNotUnreadOnly() async {
        // unreadOnly: false の場合はサーバー結果をそのまま使う
        store.unreadOnly = false
        store.articles = [makeArticle(id: 1, isRead: 1), makeArticle(id: 2, isRead: 0)]
        // サーバーは未読のみ返す（id:1 は返さない）
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 2, isRead: 0)]))
        }

        await store.refresh()

        // unreadOnly が false の場合は保持しない（サーバー結果を信頼）
        XCTAssertFalse(store.articles.contains { $0.id == 1 }, "unreadOnly=false では既読記事を保持しない")
    }

    @MainActor
    func test_fetchArticles_clearsReadArticles_whenUnreadOnly() async {
        // fetchArticles（明示的なフェッチ）は常にクリーンなサーバー結果を使う
        store.unreadOnly = true
        store.articles = [makeArticle(id: 1, isRead: 1), makeArticle(id: 2, isRead: 0)]
        // サーバーは未読のみ返す
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 2, isRead: 0)]))
        }

        await store.fetchArticles()

        // fetchArticles は既読記事を保持しない（クリーンなフェッチ）
        XCTAssertFalse(store.articles.contains { $0.id == 1 }, "明示的フェッチでは既読記事を保持しない")
        XCTAssertEqual(store.articles.count, 1)
    }
}
