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

    private func makeArticle(id: Int = 1, feedId: Int = 1, isRead: Int = 0, isFavorite: Int = 0) -> Article {
        Article(id: id, feed_id: feedId, guid: "guid-\(id)", title: "Title \(id)",
                link: nil, summary: nil, content: nil, published_at: nil,
                is_read: isRead, is_favorite: isFavorite, created_at: "2024-01-01T00:00:00Z",
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
    func test_fetchArticles_laterCallWins_whenCalledConcurrently() async {
        // 「全て→未読のみ」切り替えで2つのfetchArticlesが並行した場合、
        // 新しい方の結果が採用されること（世代カウンターによる保護）
        let allArticles = [makeArticle(id: 1, isRead: 1), makeArticle(id: 2, isRead: 0)]
        let unreadArticles = [makeArticle(id: 2, isRead: 0)]

        // 1回目: unreadOnly=false で全記事フェッチ開始（結果は後で上書きされる想定）
        store.unreadOnly = false
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(allArticles)) }
        await store.fetchArticles()

        // 2回目: unreadOnly=true で未読のみフェッチ（こちらが最新）
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(unreadArticles)) }
        await store.fetchArticles(unreadOnly: true)

        // 最後のフェッチ結果（未読のみ）が適用されていること
        XCTAssertEqual(store.articles.count, 1)
        XCTAssertFalse(store.articles.contains { $0.id == 1 }, "既読記事は未読のみモードでは表示しない")
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
        // unreadOnly: true で先にフェッチして loadedWithUnreadOnly=true を確立する
        store.unreadOnly = true
        let initial = [makeArticle(id: 1, isRead: 0), makeArticle(id: 2, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        // ユーザーが id:1 を既読にした状態を再現（楽観的更新後）
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
        // fetchArticles は常にサーバー結果をそのまま反映する（既読記事の保持は行わない）
        // 戻るボタン再表示時の保持は ArticleListView の hasAppeared フラグで制御する
        store.unreadOnly = true
        store.articles = [makeArticle(id: 1, isRead: 1), makeArticle(id: 2, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 2, isRead: 0)]))
        }

        await store.fetchArticles()

        XCTAssertFalse(store.articles.contains { $0.id == 1 }, "fetchArticles はサーバー結果をそのまま使う")
        XCTAssertEqual(store.articles.count, 1)
    }

    @MainActor
    func test_refresh_doesNotPreserveReadArticle_whenFetchArticlesCalledConcurrently() async {
        // refresh() 中に fetchArticles が外部から呼ばれた場合は保持ロジックをスキップする
        // （「全て→未読のみ」切り替え中に refresh が割り込むシナリオ）
        store.unreadOnly = true
        let initial = [makeArticle(id: 1, isRead: 0), makeArticle(id: 2, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        // ユーザーが id:1 を既読にした状態
        store.articles = [makeArticle(id: 1, isRead: 1), makeArticle(id: 2, isRead: 0)]

        // refresh() の内部 fetchArticles の後に fetchArticles(unreadOnly:false) が呼ばれることをシミュレート
        // （実際は並行だが、テストでは sequentialに再現する）
        // refresh() を模倣: previouslyReadArticles を保存後、外部 fetchArticles を先に呼ぶ
        // → genBefore + 1 != fetchGeneration になるため保持ロジックがスキップされる

        // まず「全て」fetch を実行（refresh の内部呼び出しより後に世代が進む状況を作る）
        store.unreadOnly = false
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 1, isRead: 1), self.makeArticle(id: 2, isRead: 0)]))
        }
        await store.fetchArticles()  // gen が進む

        // 「未読のみ」に戻す
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode([self.makeArticle(id: 2, isRead: 0)])) }
        await store.fetchArticles(unreadOnly: true)

        // 最終結果: 未読のみ（id:1 は表示されない）
        XCTAssertFalse(store.articles.contains { $0.id == 1 }, "全て→未読のみ切り替え後は既読記事を保持しない")
        XCTAssertEqual(store.articles.count, 1)
    }

    @MainActor
    func test_refresh_doesNotPreserveReadArticle_whenLoadedWithUnreadOnlyFalse() async {
        // unreadOnly=false で読み込んだ後に unreadOnly=true に切り替えても
        // refresh() は既読記事を保持しない（全表示モードで読んだ記事は保持対象外）
        store.unreadOnly = false
        // unreadOnly=false でフェッチ（loadedWithUnreadOnly=false が記録される）
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 1, isRead: 1), self.makeArticle(id: 2, isRead: 0)]))
        }
        await store.fetchArticles()

        // unreadOnly を true に切り替える（onChange 相当の fetchArticles はここでは省略）
        store.unreadOnly = true

        // refresh() が走る（バックグラウンド復帰など）
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 2, isRead: 0)]))
        }
        await store.refresh()

        // id:1（既読）は保持しない（全表示モードで読み込まれた記事のため）
        XCTAssertFalse(store.articles.contains { $0.id == 1 }, "全表示モードで読み込まれた既読記事は保持しない")
        XCTAssertEqual(store.articles.count, 1)
    }

    // MARK: - refreshAllArticlesCache()

    @MainActor
    func test_refreshAllArticlesCache_updatesAllArticlesWithoutChangingArticles() async {
        // articles を先に設定しておく
        store.articles = [makeArticle(id: 99, feedId: 1, isRead: 0)]

        let secretArticles = [makeArticle(id: 1, feedId: 10, isRead: 0), makeArticle(id: 2, feedId: 20, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(secretArticles)) }

        await store.refreshAllArticlesCache()

        // allArticles は更新される
        XCTAssertEqual(store.allArticles.count, 2)
        // articles は変わらない
        XCTAssertEqual(store.articles.count, 1)
        XCTAssertEqual(store.articles[0].id, 99)
    }

    @MainActor
    func test_refreshAllArticlesCache_sendsIncludeSecretTrue() async {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { req in
            capturedURL = req.url
            return (200, try JSONEncoder().encode([self.makeArticle()]))
        }

        await store.refreshAllArticlesCache()

        XCTAssertTrue(capturedURL?.query?.contains("includeSecret=true") ?? false,
                      "refreshAllArticlesCache はシークレット記事も取得するため includeSecret=true を送信すること")
    }

    @MainActor
    func test_refresh_updatesAllArticlesWithSecretArticles_whenFullFetchWithoutSecret() async {
        // includeSecret=false で全記事フェッチ（currentIncludeSecret=false を確立）
        store.unreadOnly = false
        let nonSecretArticles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(nonSecretArticles)) }
        await store.fetchArticles(includeSecret: false)

        // refresh() でシークレット記事もキャッシュされる
        let secretFeedArticle = makeArticle(id: 2, feedId: 100, isRead: 0)
        MockURLProtocol.requestHandler = { req in
            if req.url?.query?.contains("includeSecret=true") == true {
                return (200, try JSONEncoder().encode([self.makeArticle(id: 1, feedId: 1, isRead: 0), secretFeedArticle]))
            }
            return (200, try JSONEncoder().encode(nonSecretArticles))
        }

        await store.refresh()

        // allArticles にシークレットフィード（feedId=100）の記事が含まれる
        XCTAssertTrue(store.allArticles.contains { $0.feed_id == 100 },
                      "シークレットなしのフル更新後、allArticles にシークレット記事が含まれること")
    }

    @MainActor
    func test_refresh_doesNotCallRefreshAllArticlesCache_whenFeedIdIsSet() async {
        // 特定フィードの更新時は refreshAllArticlesCache を呼ばない
        let articles = [makeArticle(id: 1, feedId: 5, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }
        await store.fetchArticles(feedId: 5, includeSecret: false)

        var includeSecretRequestCount = 0
        MockURLProtocol.requestHandler = { req in
            if req.url?.query?.contains("includeSecret=true") == true {
                includeSecretRequestCount += 1
            }
            return (200, try JSONEncoder().encode(articles))
        }

        await store.refresh()

        XCTAssertEqual(includeSecretRequestCount, 0,
                       "特定フィードのフル更新時は refreshAllArticlesCache を呼ばない")
    }

    @MainActor
    func test_refresh_doesNotCallRefreshAllArticlesCache_whenIncludeSecretTrue() async {
        // includeSecret=true で取得済みの場合は refreshAllArticlesCache を呼ばない
        let articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }
        await store.fetchArticles(includeSecret: true)

        var includeSecretRequestCount = 0
        MockURLProtocol.requestHandler = { req in
            if req.url?.query?.contains("includeSecret=true") == true {
                includeSecretRequestCount += 1
            }
            return (200, try JSONEncoder().encode(articles))
        }

        await store.refresh()

        // fetchArticles 自体が includeSecret=true を 1 回送るのみ
        // refreshAllArticlesCache による追加の呼び出しはない
        XCTAssertEqual(includeSecretRequestCount, 1,
                       "includeSecret=true 取得済みの場合は refreshAllArticlesCache を追加で呼ばない")
    }

    @MainActor
    func test_refresh_doesNotCallRefreshAllArticlesCache_whenGroupIdIsSet() async {
        // 特定グループの更新時は refreshAllArticlesCache を呼ばない
        let articles = [makeArticle(id: 1, feedId: 5, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }
        await store.fetchArticles(groupId: 10, includeSecret: false)

        var includeSecretRequestCount = 0
        MockURLProtocol.requestHandler = { req in
            if req.url?.query?.contains("includeSecret=true") == true {
                includeSecretRequestCount += 1
            }
            return (200, try JSONEncoder().encode(articles))
        }

        await store.refresh()

        XCTAssertEqual(includeSecretRequestCount, 0,
                       "特定グループのフル更新時は refreshAllArticlesCache を呼ばない")
    }

    @MainActor
    func test_refresh_preservedArticles_areSortedByPublishedAt() async {
        // published_at でソートされた状態で保持されること
        // id:1 は新しい記事（既読）、id:2 は古い記事（未読）
        let newerReadArticle = Article(
            id: 1, feed_id: 1, guid: "guid-1", title: "Newer (read)",
            link: nil, summary: nil, content: nil,
            published_at: "2024-02-01T00:00:00Z", is_read: 1, is_favorite: 0,
            created_at: "2024-01-01T00:00:00Z",
            ai_summary: nil, ai_translation: nil, read_at: nil
        )
        let olderUnreadArticle = Article(
            id: 2, feed_id: 1, guid: "guid-2", title: "Older (unread)",
            link: nil, summary: nil, content: nil,
            published_at: "2024-01-01T00:00:00Z", is_read: 0, is_favorite: 0,
            created_at: "2024-01-01T00:00:00Z",
            ai_summary: nil, ai_translation: nil, read_at: nil
        )

        // loadedWithUnreadOnly=true を確立するため先にフェッチする
        store.unreadOnly = true
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode([newerReadArticle, olderUnreadArticle])) }
        await store.fetchArticles()

        // ユーザーが id:1 を既読にした状態を再現
        store.articles = [newerReadArticle, olderUnreadArticle]
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([olderUnreadArticle]))
        }

        await store.refresh()

        XCTAssertEqual(store.articles.count, 2)
        // 新しい記事（id:1）が先に来ること（published_at 降順）
        XCTAssertEqual(store.articles[0].id, 1, "新しい既読記事が先頭に来るべき")
        XCTAssertEqual(store.articles[1].id, 2, "古い未読記事が後に来るべき")
    }

    // MARK: - unreadCount(excludingFeedIds:)

    func test_unreadCount_excludingFeedIds_excludesSpecifiedFeeds() {
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0), // secret feed
            makeArticle(id: 2, feedId: 10, isRead: 0), // secret feed
            makeArticle(id: 3, feedId: 20, isRead: 0), // normal feed
            makeArticle(id: 4, feedId: 20, isRead: 1), // normal feed (read)
        ]

        // feedId=10（シークレット）を除外した未読数は 1
        XCTAssertEqual(store.unreadCount(excludingFeedIds: [10]), 1)
    }

    func test_unreadCount_excludingFeedIds_emptyExcludeSet_returnsAllUnread() {
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
            makeArticle(id: 2, feedId: 20, isRead: 0),
        ]

        // 除外なしの場合は全未読を返す
        XCTAssertEqual(store.unreadCount(excludingFeedIds: []), 2)
    }

    @MainActor
    func test_unreadCount_excludingFeedIds_usesAllArticles_whenPopulated() async {
        let feed10Articles = [makeArticle(id: 1, feedId: 10, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feed10Articles)) }
        await store.fetchArticles(feedId: 10)

        // allArticles には feedId=10 の未読1件がある
        // articles を別フィードで上書き
        store.articles = [makeArticle(id: 2, feedId: 20, isRead: 0)]

        // feedId=10 を除外 → 残るは feedId=20 だが allArticles には feedId=20 がないので 0
        XCTAssertEqual(store.unreadCount(excludingFeedIds: [10]), 0)
    }

    // MARK: - お気に入り機能

    @MainActor
    func test_favorite_optimisticallyUpdates() async {
        store.articles = [makeArticle(id: 1, isFavorite: 0)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.favorite(id: 1)

        XCTAssertTrue(store.articles[0].isFavorite)
    }

    @MainActor
    func test_favorite_rollsBackOnFailure() async {
        store.articles = [makeArticle(id: 1, isFavorite: 0)]
        MockURLProtocol.requestHandler = { _ in (500, Data()) }

        await store.favorite(id: 1)

        XCTAssertFalse(store.articles[0].isFavorite)
        XCTAssertNotNil(store.error)
    }

    @MainActor
    func test_unfavorite_optimisticallyUpdates() async {
        store.articles = [makeArticle(id: 1, isFavorite: 1)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.unfavorite(id: 1)

        XCTAssertFalse(store.articles[0].isFavorite)
    }

    @MainActor
    func test_favorite_updatesAllArticles() async {
        let favoriteArticle = makeArticle(id: 1, isFavorite: 0)
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode([favoriteArticle])) }
        await store.fetchArticles(feedId: 1)

        MockURLProtocol.requestHandler = { _ in (200, Data()) }
        await store.favorite(id: 1)

        // allArticles も更新されていること
        XCTAssertTrue(store.allArticles.first(where: { $0.id == 1 })?.isFavorite ?? false,
                      "favorite 後は allArticles にも反映される")
    }
}
