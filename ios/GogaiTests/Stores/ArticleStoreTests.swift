import XCTest
@testable import Gogai

final class ArticleStoreTests: XCTestCase {
    var client: APIClient!
    var store: ArticleStore!

    override func setUp() {
        super.setUp()
        // テスト間の UserDefaults 状態汚染を防ぐためリセット
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.unreadOnly)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.favoriteOnly)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.sortOrder)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = AppCache(directory: tempDir)
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        store = ArticleStore(cache: cache)
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
                read_at: nil)
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

    // MARK: - URLError 時の pendingReadIds 整合

    @MainActor
    func test_markAsRead_doesNotRollback_onURLError() async {
        // URLError（サーバー再起動・圏外）の場合、楽観的更新を維持し pendingReadIds に積む
        store.articles = [makeArticle(id: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }

        await store.markAsRead(id: 1)

        XCTAssertTrue(store.articles[0].isRead, "URLError ではロールバックしない")
        XCTAssertNil(store.error, "URLError では error をセットしない")
    }

    @MainActor
    func test_markAsRead_restoresReadStateOnRefetch_afterURLError() async {
        // URLError 後に fetchArticles でサーバーが未読を返しても、ローカルでは既読を維持する
        store.articles = [makeArticle(id: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        await store.markAsRead(id: 1)

        // サーバーは既読状態を受け取れていないため未読のまま返す
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 1, isRead: 0)]))
        }
        await store.fetchArticles()

        XCTAssertTrue(store.articles[0].isRead, "applyPendingReads がローカル既読を復元する")
    }

    @MainActor
    func test_markAsUnread_clearsPendingRead_onURLError() async {
        // markAsRead が URLError で pendingReadIds に積まれた直後にユーザーが「未読に戻す」を実行。
        // markAsUnread も URLError で失敗した場合でも、再フェッチ時にローカル既読が復活してはいけない
        // （pendingReadIds から該当 ID を取り除く必要がある）
        store.articles = [makeArticle(id: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        await store.markAsRead(id: 1)            // pendingReadIds に積まれる
        await store.markAsUnread(id: 1)          // pendingReadIds から外れるべき

        // 直後の状態で未読になっていること（楽観的更新を維持）
        XCTAssertFalse(store.articles[0].isRead, "URLError でも未読の楽観更新は保持する")

        // サーバーは未読を返す
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 1, isRead: 0)]))
        }
        await store.fetchArticles()

        XCTAssertFalse(store.articles[0].isRead, "未読操作の意図を尊重し、再フェッチで既読に戻してはいけない")
    }

    // MARK: - mergeIntoAllArticles の分岐（再設計前の特性固定）

    @MainActor
    func test_fetchArticles_feedSpecific_replacesOnlyThatFeedInAllArticles() async {
        // 全件フェッチで feed 1 と feed 2 の記事を allArticles に入れる
        let initial = [makeArticle(id: 1, feedId: 1), makeArticle(id: 2, feedId: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()
        XCTAssertEqual(store.allArticles.count, 2)

        // feed 1 のみフェッチ: feed 1 の記事が差し替わり、feed 2 の記事は保持される
        let feed1New = [makeArticle(id: 10, feedId: 1), makeArticle(id: 11, feedId: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feed1New)) }
        await store.fetchArticles(feedId: 1)

        let allIds = Set(store.allArticles.map { $0.id })
        XCTAssertEqual(allIds, [2, 10, 11], "feed 1 は新記事に差し替え、feed 2 は保持")
    }

    @MainActor
    func test_fetchArticles_groupSpecific_replacesFetchedFeedsInAllArticles() async {
        // feed 1（グループ内）と feed 9（グループ外）を allArticles に入れる
        let initial = [makeArticle(id: 1, feedId: 1), makeArticle(id: 9, feedId: 9)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        // groupId 指定フェッチが feed 1 の記事を返す → feed 9 は保持される
        let groupArticles = [makeArticle(id: 100, feedId: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(groupArticles)) }
        await store.fetchArticles(groupId: 5)

        let allIds = Set(store.allArticles.map { $0.id })
        XCTAssertEqual(allIds, [9, 100], "フェッチ結果に含まれるフィードのみ差し替える")
    }

    @MainActor
    func test_fetchArticles_fullFetch_replacesAllArticlesEntirely() async {
        let initial = [makeArticle(id: 1, feedId: 1), makeArticle(id: 2, feedId: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        let next = [makeArticle(id: 3, feedId: 3)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(next)) }
        await store.fetchArticles()

        XCTAssertEqual(store.allArticles.map { $0.id }, [3], "全件フェッチは全置換")
    }

    // MARK: - markAsRead / markAllAsRead と allArticles の同期

    @MainActor
    func test_markAsRead_updatesAllArticles() async {
        let initial = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        MockURLProtocol.requestHandler = { _ in (200, Data()) }
        await store.markAsRead(id: 1)

        XCTAssertTrue(store.allArticles[0].isRead, "allArticles も同期して既読になる")
    }

    @MainActor
    func test_markAllAsRead_marksAllUnreadAndSyncsAllArticles() async {
        let initial = [
            makeArticle(id: 1, feedId: 1, isRead: 0),
            makeArticle(id: 2, feedId: 1, isRead: 1),
            makeArticle(id: 3, feedId: 1, isRead: 0),
        ]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        MockURLProtocol.requestHandler = { _ in (200, Data()) }
        await store.markAllAsRead()

        XCTAssertTrue(store.articles.allSatisfy { $0.isRead })
        XCTAssertTrue(store.allArticles.allSatisfy { $0.isRead }, "allArticles も全て既読")
        XCTAssertNotNil(store.articles[0].read_at, "既読化で read_at が設定される")
        XCTAssertEqual(store.articles[1].read_at, nil, "元から既読の記事は read_at を上書きしない")
    }

    @MainActor
    func test_markAllAsRead_onURLError_keepsOptimisticUpdate() async {
        let initial = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(initial)) }
        await store.fetchArticles()

        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        await store.markAllAsRead()

        XCTAssertTrue(store.articles[0].isRead, "URLError ではロールバックせず pending に積む")
    }

    func test_badgeCount_unreadOnly_returnsCorrectCount() {
        store.unreadOnly = true
        store.articles = [
            makeArticle(id: 1, isRead: 0),
            makeArticle(id: 2, isRead: 1),
            makeArticle(id: 3, isRead: 0),
        ]

        XCTAssertEqual(store.badgeCount(for: nil), 2)
    }

    // MARK: - unreadCount(forGroupFeedIds:)

    func test_badgeCount_unreadOnly_forGroupFeedIds_returnsUnreadCountForSpecifiedFeeds() {
        store.unreadOnly = true
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
            makeArticle(id: 2, feedId: 10, isRead: 1),
            makeArticle(id: 3, feedId: 20, isRead: 0),
            makeArticle(id: 4, feedId: 30, isRead: 0),
        ]

        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10, 20]), 2)
    }

    func test_badgeCount_unreadOnly_forGroupFeedIds_excludesFeedsNotInGroup() {
        store.unreadOnly = true
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
            makeArticle(id: 2, feedId: 20, isRead: 0),
        ]

        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10]), 1)
    }

    func test_badgeCount_unreadOnly_forGroupFeedIds_returnsZeroForEmptyFeedIds() {
        store.unreadOnly = true
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
        ]

        XCTAssertEqual(store.badgeCount(forGroupFeedIds: []), 0)
    }

    func test_badgeCount_unreadOnly_forGroupFeedIds_fallsBackToArticles_whenAllArticlesEmpty() {
        store.unreadOnly = true
        store.articles = [makeArticle(id: 1, feedId: 10, isRead: 0)]
        // allArticles が空の場合は articles を使う
        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10]), 1)
    }

    @MainActor
    func test_badgeCount_unreadOnly_forGroupFeedIds_usesAllArticles_whenAllArticlesPopulated() async {
        // fetchArticles で allArticles を feed_id=10 の記事で埋める
        // （フィルタ中はコレクションを更新しない仕様のため、フェッチはフィルタなしで行う）
        let feed10Articles = [makeArticle(id: 1, feedId: 10, isRead: 0), makeArticle(id: 2, feedId: 10, isRead: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feed10Articles)) }
        await store.fetchArticles(feedId: 10)
        store.unreadOnly = true

        // articles は feed_id=10 のみ、allArticles も feed_id=10 が入っている
        // articles を feed_id=20 で上書き（allArticles は更新されない）
        store.articles = [makeArticle(id: 3, feedId: 20, isRead: 0)]

        // allArticles（feed_id=10 の未読1件）を使う
        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10]), 1)
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

    @MainActor
    func test_refresh_preservedArticles_areSortedByPublishedAt() async {
        // published_at でソートされた状態で保持されること
        // id:1 は新しい記事（既読）、id:2 は古い記事（未読）
        let newerReadArticle = Article(
            id: 1, feed_id: 1, guid: "guid-1", title: "Newer (read)",
            link: nil, summary: nil, content: nil,
            published_at: "2024-02-01T00:00:00Z", is_read: 1, is_favorite: 0,
            created_at: "2024-01-01T00:00:00Z", read_at: nil
        )
        let olderUnreadArticle = Article(
            id: 2, feed_id: 1, guid: "guid-2", title: "Older (unread)",
            link: nil, summary: nil, content: nil,
            published_at: "2024-01-01T00:00:00Z", is_read: 0, is_favorite: 0,
            created_at: "2024-01-01T00:00:00Z", read_at: nil
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

    // MARK: - favoriteOnly と allArticles の独立性

    @MainActor
    func test_fetchArticles_favoriteOnly_doesNotUpdateAllArticles() async {
        // 事前に全記事を allArticles に設定
        let allArticlesData = [makeArticle(id: 1, feedId: 1), makeArticle(id: 2, feedId: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(allArticlesData)) }
        await store.fetchArticles(feedId: 1)
        let beforeCount = store.allArticles.count
        XCTAssertEqual(beforeCount, 2)

        // favoriteOnly=true でフェッチしても allArticles を上書きしない
        let favoritesOnly = [makeArticle(id: 1, feedId: 1, isFavorite: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(favoritesOnly)) }
        store.favoriteOnly = true
        await store.fetchArticles(feedId: 1)

        XCTAssertEqual(store.articles.count, 1)
        XCTAssertEqual(store.allArticles.count, beforeCount, "favoriteOnly=true 時は allArticles を更新しない")
    }

    @MainActor
    func test_fetchArticles_afterFavoriteOnlyDisabled_updatesAllArticles() async {
        // favoriteOnly=false に戻したら allArticles を再度更新する
        let allArticlesData = [makeArticle(id: 1, feedId: 1), makeArticle(id: 2, feedId: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(allArticlesData)) }
        store.favoriteOnly = false
        await store.fetchArticles(feedId: 1)

        XCTAssertEqual(store.allArticles.count, 2, "favoriteOnly=false の場合は allArticles を更新する")
    }

    @MainActor
    func test_fetchArticles_unreadOnly_doesNotUpdateAllArticles() async {
        // 全件（フィルタなし）フェッチで allArticles に既読・未読を両方入れる
        let full = [makeArticle(id: 1, feedId: 1, isRead: 1), makeArticle(id: 2, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(full)) }
        await store.fetchArticles()
        XCTAssertEqual(store.allArticles.count, 2)

        // unreadOnly=true でフェッチすると未読のみが返るが、allArticles を未読だけに汚染してはいけない
        // （汚染すると「お気に入りのみ」表示時に既読のお気に入りを持つフィードが消える）
        let unreadResult = [makeArticle(id: 2, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(unreadResult)) }
        await store.fetchArticles(unreadOnly: true)

        XCTAssertEqual(store.articles.count, 1, "表示中リストは未読のみ")
        XCTAssertEqual(store.allArticles.count, 2, "unreadOnly=true 時は allArticles を未読だけで上書きしない")
    }

    @MainActor
    func test_hasVisibleArticle_favoriteOnly_findsReadFavorite_afterUnreadFetch() async {
        // 全件フェッチ: feed 10 は既読のお気に入り、feed 20 は未読の通常記事
        let full = [
            makeArticle(id: 1, feedId: 10, isRead: 1, isFavorite: 1),
            makeArticle(id: 2, feedId: 20, isRead: 0, isFavorite: 0),
        ]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(full)) }
        await store.fetchArticles()

        // 未読のみでフェッチ（feed 20 のみ返る）→ allArticles を汚染しないこと
        let unreadResult = [makeArticle(id: 2, feedId: 20, isRead: 0, isFavorite: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(unreadResult)) }
        await store.fetchArticles(unreadOnly: true)

        // お気に入りのみに切り替え
        store.unreadOnly = false
        store.favoriteOnly = true

        XCTAssertTrue(store.hasVisibleArticle(for: 10),
                      "既読のお気に入り記事を持つフィードはお気に入り表示で見える")
    }

    // MARK: - hasVisibleArticle(for:)

    func test_hasVisibleArticle_noFilters_returnsTrue() {
        store.articles = []
        store.unreadOnly = false
        store.favoriteOnly = false
        XCTAssertTrue(store.hasVisibleArticle(for: 1), "フィルタ未指定時は常に表示する")
    }

    func test_hasVisibleArticle_unreadOnly_feedHasUnread_returnsTrue() {
        store.articles = [makeArticle(id: 1, feedId: 10, isRead: 0)]
        store.unreadOnly = true
        XCTAssertTrue(store.hasVisibleArticle(for: 10))
    }

    func test_hasVisibleArticle_unreadOnly_feedAllRead_returnsFalse() {
        store.articles = [makeArticle(id: 1, feedId: 10, isRead: 1)]
        store.unreadOnly = true
        XCTAssertFalse(store.hasVisibleArticle(for: 10))
    }

    func test_hasVisibleArticle_favoriteOnly_feedHasFavorite_returnsTrue() {
        store.articles = [makeArticle(id: 1, feedId: 10, isFavorite: 1)]
        store.favoriteOnly = true
        XCTAssertTrue(store.hasVisibleArticle(for: 10))
    }

    func test_hasVisibleArticle_favoriteOnly_feedNoFavorite_returnsFalse() {
        store.articles = [makeArticle(id: 1, feedId: 10, isFavorite: 0)]
        store.favoriteOnly = true
        XCTAssertFalse(store.hasVisibleArticle(for: 10))
    }

    func test_hasVisibleArticle_combinedFilters_appliesAndLogic() {
        // 未読 + お気に入り が必要
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0, isFavorite: 0),    // 未読だがお気に入りでない
            makeArticle(id: 2, feedId: 10, isRead: 1, isFavorite: 1),    // お気に入りだが既読
            makeArticle(id: 3, feedId: 20, isRead: 0, isFavorite: 1),    // 未読 + お気に入り
        ]
        store.unreadOnly = true
        store.favoriteOnly = true
        XCTAssertFalse(store.hasVisibleArticle(for: 10), "片方しか満たさない記事しかないフィードは非表示")
        XCTAssertTrue(store.hasVisibleArticle(for: 20), "両方満たす記事があるフィードは表示")
    }

    @MainActor
    func test_hasVisibleArticle_usesAllArticles_whenPopulated() async {
        // allArticles にお気に入り記事を入れた状態を作る
        let articles = [makeArticle(id: 1, feedId: 10, isFavorite: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }
        await store.fetchArticles()

        // articles を別フィードで上書きしても allArticles 経由で feedId=10 を判定できる
        store.articles = [makeArticle(id: 99, feedId: 99)]
        store.favoriteOnly = true
        XCTAssertTrue(store.hasVisibleArticle(for: 10))
    }

    // MARK: - badgeCount（フィルタ連動のバッジ件数）

    private func seedBadgeArticles() {
        // feed 10: 未読1 / 既読お気に入り1 / 既読1 = 計3
        // feed 20: 未読1 = 計1
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0, isFavorite: 0),
            makeArticle(id: 2, feedId: 10, isRead: 1, isFavorite: 1),
            makeArticle(id: 3, feedId: 10, isRead: 1, isFavorite: 0),
            makeArticle(id: 4, feedId: 20, isRead: 0, isFavorite: 0),
        ]
    }

    func test_badgeCount_全て選択時は全記事数を返す() {
        seedBadgeArticles()
        store.unreadOnly = false
        store.favoriteOnly = false
        XCTAssertEqual(store.badgeCount(for: 10), 3)
        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10, 20]), 4)
        XCTAssertEqual(store.badgeCount(excludingFeedIds: [20]), 3)
    }

    func test_badgeCount_未読のみ選択時は未読数を返す() {
        seedBadgeArticles()
        store.unreadOnly = true
        store.favoriteOnly = false
        XCTAssertEqual(store.badgeCount(for: 10), 1)
        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10, 20]), 2)
        XCTAssertEqual(store.badgeCount(excludingFeedIds: [20]), 1)
    }

    func test_badgeCount_お気に入り選択時はお気に入り数を返す() {
        seedBadgeArticles()
        store.unreadOnly = false
        store.favoriteOnly = true
        XCTAssertEqual(store.badgeCount(for: 10), 1)
        XCTAssertEqual(store.badgeCount(for: 20), 0)
        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [10, 20]), 1)
        XCTAssertEqual(store.badgeCount(excludingFeedIds: []), 1)
    }

    @MainActor
    func test_badgeCount_allArticlesがあればそちらを使う() async {
        let all = [
            makeArticle(id: 1, feedId: 10, isRead: 1, isFavorite: 1),
            makeArticle(id: 2, feedId: 10, isRead: 0, isFavorite: 0),
        ]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(all)) }
        await store.fetchArticles()

        store.articles = []  // 表示中リストが空でもキャッシュから数えられる
        store.favoriteOnly = true
        XCTAssertEqual(store.badgeCount(for: 10), 1)
    }

    // MARK: - unreadCount(excludingFeedIds:)

    func test_badgeCount_unreadOnly_excludingFeedIds_excludesSpecifiedFeeds() {
        store.unreadOnly = true
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0), // secret feed
            makeArticle(id: 2, feedId: 10, isRead: 0), // secret feed
            makeArticle(id: 3, feedId: 20, isRead: 0), // normal feed
            makeArticle(id: 4, feedId: 20, isRead: 1), // normal feed (read)
        ]

        // feedId=10（シークレット）を除外した未読数は 1
        XCTAssertEqual(store.badgeCount(excludingFeedIds: [10]), 1)
    }

    func test_badgeCount_unreadOnly_excludingFeedIds_emptyExcludeSet_returnsAllUnread() {
        store.unreadOnly = true
        store.articles = [
            makeArticle(id: 1, feedId: 10, isRead: 0),
            makeArticle(id: 2, feedId: 20, isRead: 0),
        ]

        // 除外なしの場合は全未読を返す
        XCTAssertEqual(store.badgeCount(excludingFeedIds: []), 2)
    }

    @MainActor
    func test_badgeCount_unreadOnly_excludingFeedIds_usesAllArticles_whenPopulated() async {
        // フィルタ中はコレクションを更新しない仕様のため、フェッチはフィルタなしで行う
        let feed10Articles = [makeArticle(id: 1, feedId: 10, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(feed10Articles)) }
        await store.fetchArticles(feedId: 10)
        store.unreadOnly = true

        // allArticles には feedId=10 の未読1件がある
        // articles を別フィードで上書き
        store.articles = [makeArticle(id: 2, feedId: 20, isRead: 0)]

        // feedId=10 を除外 → 残るは feedId=20 だが allArticles には feedId=20 がないので 0
        XCTAssertEqual(store.badgeCount(excludingFeedIds: [10]), 0)
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

    // MARK: - キャッシュ

    private func makeTmpCache() -> (AppCache, URL) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return (AppCache(directory: tmpDir), tmpDir)
    }

    func test_init_loadsAllArticlesFromCache() {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cachedArticles = [makeArticle(id: 99, feedId: 5, isRead: 0)]
        testCache.saveAllArticles(cachedArticles)

        let storeWithCache = ArticleStore(cache: testCache)

        XCTAssertEqual(storeWithCache.allArticles.count, 1, "起動時にキャッシュから allArticles を読み込むこと")
        XCTAssertEqual(storeWithCache.allArticles[0].id, 99)
    }

    @MainActor
    func test_fetchArticles_savesAllArticlesToCache() async {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let storeWithCache = ArticleStore(cache: testCache)
        storeWithCache.configure(with: client)

        let articles = [makeArticle(id: 1), makeArticle(id: 2)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }

        await storeWithCache.fetchArticles()

        let cached = testCache.loadAllArticles()
        XCTAssertEqual(cached.count, 2, "fetchArticles 後にキャッシュが保存されること")
    }

    // MARK: - feedCounts（サーバー集計）

    private func makeCount(feedId: Int, total: Int, unread: Int, favorite: Int) -> FeedCount {
        FeedCount(feed_id: feedId, total: total, unread: unread, favorite: favorite)
    }

    @MainActor
    func test_refreshCounts_updatesFeedCounts() async {
        let counts = [makeCount(feedId: 1, total: 3, unread: 2, favorite: 1),
                      makeCount(feedId: 2, total: 5, unread: 0, favorite: 0)]
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/api/articles/counts") == true)
            return (200, try JSONEncoder().encode(counts))
        }

        await store.refreshCounts()

        XCTAssertEqual(store.feedCounts[1]?.unread, 2)
        XCTAssertEqual(store.feedCounts[2]?.total, 5)
        XCTAssertNil(store.error)
    }

    @MainActor
    func test_refreshCounts_keepsPreviousCounts_onFailure() async {
        let counts = [makeCount(feedId: 1, total: 3, unread: 2, favorite: 1)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(counts)) }
        await store.refreshCounts()

        MockURLProtocol.requestHandler = { _ in (500, Data()) }
        await store.refreshCounts()

        XCTAssertEqual(store.feedCounts[1]?.unread, 2, "失敗時は前回値を維持する")
        XCTAssertNil(store.error, "counts はベストエフォートなので error を立てない")
    }

    /// refreshCounts 経由で feedCounts を投入するヘルパー
    @MainActor
    private func seedCounts(_ counts: [FeedCount]) async {
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(counts)) }
        await store.refreshCounts()
        MockURLProtocol.requestHandler = nil
    }

    @MainActor
    func test_badgeCount_usesFeedCounts_perFilter() async {
        await seedCounts([makeCount(feedId: 1, total: 10, unread: 4, favorite: 2)])

        // allCollection は空でも counts があればバッジが出る（起動直後の 0 件表示の修正点）
        XCTAssertEqual(store.badgeCount(for: 1), 10, "「全て」= total")

        store.unreadOnly = true
        XCTAssertEqual(store.badgeCount(for: 1), 4, "「未読のみ」= unread")

        store.unreadOnly = false
        store.favoriteOnly = true
        XCTAssertEqual(store.badgeCount(for: 1), 2, "「お気に入り」= favorite")
    }

    @MainActor
    func test_badgeCount_aggregates_acrossFeeds() async {
        await seedCounts([makeCount(feedId: 1, total: 3, unread: 1, favorite: 0),
                          makeCount(feedId: 2, total: 5, unread: 2, favorite: 1),
                          makeCount(feedId: 3, total: 7, unread: 4, favorite: 0)])
        store.unreadOnly = true

        XCTAssertEqual(store.badgeCount(for: nil), 7, "全フィード合計")
        XCTAssertEqual(store.badgeCount(forGroupFeedIds: [1, 2]), 3, "グループ = 所属フィードの合計")
        XCTAssertEqual(store.badgeCount(excludingFeedIds: [3]), 3, "除外指定フィード以外の合計")
        XCTAssertEqual(store.badgeCount(for: 99), 0, "counts に無いフィードは 0")
    }

    @MainActor
    func test_hasVisibleArticle_usesFeedCounts() async {
        await seedCounts([makeCount(feedId: 1, total: 3, unread: 0, favorite: 1),
                          makeCount(feedId: 2, total: 2, unread: 2, favorite: 0)])
        store.unreadOnly = true

        XCTAssertFalse(store.hasVisibleArticle(for: 1), "未読 0 のフィードは非表示")
        XCTAssertTrue(store.hasVisibleArticle(for: 2))

        store.unreadOnly = false
        store.favoriteOnly = true
        XCTAssertTrue(store.hasVisibleArticle(for: 1))
        XCTAssertFalse(store.hasVisibleArticle(for: 2), "お気に入り 0 のフィードは非表示")
    }

    @MainActor
    func test_badgeCount_fallsBackToCollection_whenBothFiltersActive() async {
        // UI からは到達不能だが、counts の 3 値では AND 条件を表現できないため
        // 両フィルタ有効時は従来のコレクション計算にフォールバックする
        await seedCounts([makeCount(feedId: 1, total: 10, unread: 4, favorite: 2)])
        MockURLProtocol.requestHandler = { _ in
            (200, try JSONEncoder().encode([self.makeArticle(id: 1, feedId: 1, isRead: 0, isFavorite: 1),
                                            self.makeArticle(id: 2, feedId: 1, isRead: 0, isFavorite: 0)]))
        }
        await store.fetchArticles()

        store.unreadOnly = true
        store.favoriteOnly = true

        XCTAssertEqual(store.badgeCount(for: 1), 1, "未読かつお気に入りはコレクションから数える")
    }

    // MARK: - feedCounts と楽観更新の同期

    @MainActor
    func test_markAsRead_decrementsUnreadCount() async {
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 2, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.markAsRead(id: 1)

        XCTAssertEqual(store.feedCounts[1]?.unread, 1)
        XCTAssertEqual(store.feedCounts[1]?.total, 5, "total は変わらない")
    }

    @MainActor
    func test_markAsRead_restoresUnreadCount_onRollback() async {
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 2, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (500, Data()) }

        await store.markAsRead(id: 1)

        XCTAssertEqual(store.feedCounts[1]?.unread, 2, "ロールバックで counts も元に戻る")
    }

    @MainActor
    func test_markAsRead_keepsDecrement_onURLError() async {
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 2, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }

        await store.markAsRead(id: 1)

        XCTAssertEqual(store.feedCounts[1]?.unread, 1, "URLError（pending 積み）でも減算は維持")
    }

    @MainActor
    func test_markAsUnread_incrementsUnreadCount() async {
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 2, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 1)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.markAsUnread(id: 1)

        XCTAssertEqual(store.feedCounts[1]?.unread, 3)
    }

    @MainActor
    func test_favoriteAndUnfavorite_adjustFavoriteCount() async {
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 2, favorite: 1)])
        store.articles = [makeArticle(id: 1, feedId: 1, isFavorite: 0), makeArticle(id: 2, feedId: 1, isFavorite: 1)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.favorite(id: 1)
        XCTAssertEqual(store.feedCounts[1]?.favorite, 2)

        await store.unfavorite(id: 2)
        XCTAssertEqual(store.feedCounts[1]?.favorite, 1)
        XCTAssertEqual(store.feedCounts[1]?.unread, 2, "unread は変わらない")
    }

    @MainActor
    func test_markAllAsRead_decrementsUnreadPerFeed() async {
        await seedCounts([makeCount(feedId: 1, total: 3, unread: 2, favorite: 0),
                          makeCount(feedId: 2, total: 3, unread: 3, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 0),
                          makeArticle(id: 2, feedId: 1, isRead: 0),
                          makeArticle(id: 3, feedId: 2, isRead: 0),
                          makeArticle(id: 4, feedId: 2, isRead: 1)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.markAllAsRead()

        XCTAssertEqual(store.feedCounts[1]?.unread, 0)
        XCTAssertEqual(store.feedCounts[2]?.unread, 2, "既読だった記事は減算しない")
    }

    @MainActor
    func test_unreadCount_clampsAtZero() async {
        // サーバー集計とローカル記事の状態がずれていても 0 未満にならない
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 0, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, Data()) }

        await store.markAsRead(id: 1)

        XCTAssertEqual(store.feedCounts[1]?.unread, 0)
    }

    @MainActor
    func test_refreshCounts_subtractsPendingReads() async {
        // URLError で pending 中の既読はサーバー集計に未反映のため、フェッチ後に減算する
        await seedCounts([makeCount(feedId: 1, total: 5, unread: 2, favorite: 0)])
        store.articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        await store.markAsRead(id: 1)

        // サーバーはまだ未読 2 と答えるが、pending 分を引いて 1 になる
        let counts = [makeCount(feedId: 1, total: 5, unread: 2, favorite: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(counts)) }
        await store.refreshCounts()

        XCTAssertEqual(store.feedCounts[1]?.unread, 1)
    }

    @MainActor
    func test_refresh_alsoRefreshesCounts() async {
        let articles = [makeArticle(id: 1, feedId: 1, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }
        await store.fetchArticles()

        let counts = [makeCount(feedId: 1, total: 9, unread: 6, favorite: 0)]
        MockURLProtocol.requestHandler = { req in
            if req.url?.path.hasSuffix("/api/articles/counts") == true {
                return (200, try JSONEncoder().encode(counts))
            }
            return (200, try JSONEncoder().encode(articles))
        }

        await store.refresh()

        XCTAssertEqual(store.feedCounts[1]?.unread, 6, "refresh() でサーバー集計も更新される")
    }

    @MainActor
    func test_refresh_refreshesCounts_evenWhenFeedIdIsSet() async {
        // 特定フィード表示中の refresh でも counts はグローバルに更新する
        // （他フィードの新着がバッジに反映されない「バッジ凍結」を防ぐ）
        let articles = [makeArticle(id: 1, feedId: 5, isRead: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(articles)) }
        await store.fetchArticles(feedId: 5)

        let counts = [makeCount(feedId: 7, total: 3, unread: 3, favorite: 0)]
        MockURLProtocol.requestHandler = { req in
            if req.url?.path.hasSuffix("/api/articles/counts") == true {
                return (200, try JSONEncoder().encode(counts))
            }
            return (200, try JSONEncoder().encode(articles))
        }

        await store.refresh()

        XCTAssertEqual(store.feedCounts[7]?.unread, 3, "表示外フィードの counts も更新される")
    }

    @MainActor
    func test_refreshCounts_savesToCache_andInitRestores() async {
        let (testCache, tmpDir) = makeTmpCache()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let storeWithCache = ArticleStore(cache: testCache)
        storeWithCache.configure(with: client)
        let counts = [makeCount(feedId: 7, total: 4, unread: 3, favorite: 0)]
        MockURLProtocol.requestHandler = { _ in (200, try JSONEncoder().encode(counts)) }

        await storeWithCache.refreshCounts()

        XCTAssertEqual(testCache.loadFeedCounts(), counts, "refreshCounts 後にキャッシュへ保存される")

        let restored = ArticleStore(cache: testCache)
        XCTAssertEqual(restored.feedCounts[7]?.unread, 3, "起動時にキャッシュから feedCounts を復元する")
    }
}
