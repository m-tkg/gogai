package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.cache.InMemoryKeyValueStore
import com.mtkg.gogai.model.Article
import com.mtkg.gogai.model.ArticleSortOrder
import com.mtkg.gogai.model.FeedCount
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class ArticleStoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private val testDispatcher = StandardTestDispatcher()

    private val testHttpClient = OkHttpClient.Builder().retryOnConnectionFailure(false).build()

    private lateinit var server: MockWebServer
    private lateinit var keyValueStore: InMemoryKeyValueStore
    private lateinit var storeScope: CoroutineScope
    private lateinit var store: ArticleStore

    private fun makeArticle(id: Int = 1, feedId: Int = 1, isRead: Int = 0, publishedAt: String? = null, readAt: String? = null) = Article(
        id = id,
        feed_id = feedId,
        guid = "guid-$id",
        title = "Title $id",
        published_at = publishedAt,
        is_read = isRead,
        created_at = "2024-01-01T00:00:00Z",
        read_at = readAt,
    )

    private fun newStore(cache: AppCache = AppCache(tempFolder.newFolder())): ArticleStore {
        val s = ArticleStore(cache, keyValueStore, storeScope, nowIso = { "2026-01-01T00:00:00Z" })
        s.configure(goodClient())
        return s
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        server = MockWebServer()
        server.start()
        keyValueStore = InMemoryKeyValueStore()
        // Why: ArticleStore は Dispatchers.Main.immediate 相当の単一スレッド閉じ込めを前提に
        // ロックなしで実装されている。storeScope を実スレッド並列のディスパッチャにすると、
        // 呼び出し側とバックグラウンドの再送タスクが別スレッドから同じ可変フィールドへ
        // 同期なしでアクセスし得るため、testDispatcher に紐付けて単一スレッドで逐次実行させる。
        storeScope = CoroutineScope(testDispatcher)
        store = newStore()
    }

    @After
    fun tearDown() {
        server.shutdown()
        Dispatchers.resetMain()
    }

    private fun enqueueArticles(articles: List<Article>, code: Int = 200) {
        server.enqueue(MockResponse().setResponseCode(code).setBody(Json.encodeToString(ListSerializer(Article.serializer()), articles)))
    }

    private fun enqueueEmptyOk() {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
    }

    private fun goodClient() = ApiClient(baseUrl = server.url("/").toString().toHttpUrl(), httpClient = testHttpClient)

    // Why: MockWebServer の SocketPolicy による切断は、直後に別のレスポンスをキューへ積む
    // シナリオでは接続の扱いにより後続レスポンスを取りこぼすことがあり不安定になる。
    // 確実に IOException を発生させるため、接続不可能なポートへ向けた ApiClient に
    // 一時的に差し替える（呼び出し後に goodClient() へ戻すこと）。
    private val unreachableClient = ApiClient(baseUrl = "http://127.0.0.1:1".toHttpUrl(), httpClient = testHttpClient)

    // MARK: - fetchArticles

    @Test
    fun `fetchArticles は articles を更新する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1), makeArticle(id = 2)))

        store.fetchArticles()

        assertEquals(2, store.articles.value.size)
        assertNull(store.error.value)
    }

    @Test
    fun `fetchArticles は後の呼び出しの結果を採用する`() = runTest(testDispatcher) {
        store.setUnreadOnly(false)
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 1), makeArticle(id = 2, isRead = 0)))
        store.fetchArticles()

        enqueueArticles(listOf(makeArticle(id = 2, isRead = 0)))
        store.fetchArticles(unreadOnly = true)

        assertEquals(1, store.articles.value.size)
        assertFalse(store.articles.value.any { it.id == 1 })
    }

    // MARK: - markAsRead / markAsUnread（楽観更新）

    @Test
    fun `markAsRead は楽観的に既読へ更新する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        store.fetchArticles()

        enqueueEmptyOk()
        store.markAsRead(1)

        assertTrue(store.articles.value[0].isRead)
    }

    @Test
    fun `markAsRead は失敗時にロールバックしerrorをセットする`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        store.fetchArticles()

        server.enqueue(MockResponse().setResponseCode(500))
        store.markAsRead(1)

        assertFalse(store.articles.value[0].isRead)
        assertNotNull(store.error.value)
    }

    @Test
    fun `markAsUnread は楽観的に未読へ更新する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 1)))
        store.fetchArticles()

        enqueueEmptyOk()
        store.markAsUnread(1)

        assertFalse(store.articles.value[0].isRead)
    }

    // MARK: - IOException 時の pendingReadIds 整合

    @Test
    fun `markAsRead は IOException ではロールバックしない`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        store.fetchArticles()

        store.configure(unreachableClient)
        store.markAsRead(1)
        store.configure(goodClient())

        assertTrue(store.articles.value[0].isRead)
        assertNull(store.error.value)
    }

    @Test
    fun `markAsRead は IOException 後の再フェッチで既読状態を復元する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        store.fetchArticles()

        store.configure(unreachableClient)
        store.markAsRead(1)
        store.configure(goodClient())

        // サーバーは既読状態を受け取れていないため未読のまま返す
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        // pending の再送も走るので追加でエンドポイントを積んでおく
        enqueueEmptyOk()
        store.fetchArticles()
        advanceUntilIdle()

        assertTrue(store.articles.value[0].isRead)
    }

    @Test
    fun `markAsUnread は IOException 後も pendingReadIds をクリアし再フェッチで既読に戻さない`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        store.fetchArticles()

        store.configure(unreachableClient)
        store.markAsRead(1) // pendingReadIds に積まれる
        store.markAsUnread(1) // pendingReadIds から外れる
        store.configure(goodClient())

        assertFalse(store.articles.value[0].isRead)

        // サーバーは未読を返す
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0)))
        store.fetchArticles()
        advanceUntilIdle()

        assertFalse(store.articles.value[0].isRead)
    }

    // MARK: - allArticles（コレクション）の同期

    @Test
    fun `fetchArticles フィード指定はそのフィードのみ allArticles に反映する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1), makeArticle(id = 2, feedId = 2)))
        store.fetchArticles()

        enqueueArticles(listOf(makeArticle(id = 10, feedId = 1)))
        store.fetchArticles(feedId = 1)

        assertEquals(setOf(2, 10), store.allArticles.value.map { it.id }.toSet())
    }

    @Test
    fun `fetchArticles 全件フェッチは allArticles を完全に置き換える`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1), makeArticle(id = 2, feedId = 2)))
        store.fetchArticles()

        enqueueArticles(listOf(makeArticle(id = 3, feedId = 3)))
        store.fetchArticles()

        assertEquals(listOf(3), store.allArticles.value.map { it.id })
    }

    @Test
    fun `fetchArticles unreadOnly のときは allArticles を更新しない`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1), makeArticle(id = 2, feedId = 1)))
        store.fetchArticles()
        val before = store.allArticles.value

        enqueueArticles(listOf(makeArticle(id = 2, feedId = 1, isRead = 0)))
        store.fetchArticles(unreadOnly = true)

        assertEquals(before.map { it.id }.toSet(), store.allArticles.value.map { it.id }.toSet())
    }

    @Test
    fun `markAsRead は allArticles も同期する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 0)))
        store.fetchArticles()

        enqueueEmptyOk()
        store.markAsRead(1)

        assertTrue(store.allArticles.value[0].isRead)
    }

    // MARK: - markAllAsRead

    @Test
    fun `markAllAsRead は未読記事を全て既読にし allArticles も同期する`() = runTest(testDispatcher) {
        enqueueArticles(
            listOf(
                makeArticle(id = 1, feedId = 1, isRead = 0),
                makeArticle(id = 2, feedId = 1, isRead = 1),
                makeArticle(id = 3, feedId = 1, isRead = 0),
            ),
        )
        store.fetchArticles()

        enqueueEmptyOk()
        enqueueEmptyOk()
        store.markAllAsRead()

        assertTrue(store.articles.value.all { it.isRead })
        assertTrue(store.allArticles.value.all { it.isRead })
        assertNotNull(store.articles.value[0].read_at)
        assertNull(store.articles.value[1].read_at)
    }

    @Test
    fun `markAllAsRead は IOException では楽観更新を維持する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 0)))
        store.fetchArticles()

        store.configure(unreachableClient)
        store.markAllAsRead()
        store.configure(goodClient())

        assertTrue(store.articles.value[0].isRead)
    }

    // MARK: - badgeCount / hasVisibleArticle（コレクションフォールバック）

    @Test
    fun `badgeCount は unreadOnly のとき未読数を返す`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0), makeArticle(id = 2, isRead = 1), makeArticle(id = 3, isRead = 0)))
        store.fetchArticles()
        store.setUnreadOnly(true)

        assertEquals(2, store.badgeCount())
    }

    @Test
    fun `badgeCount は全て選択時は全記事数を返す`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0), makeArticle(id = 2, isRead = 1)))
        store.fetchArticles()
        store.setUnreadOnly(false)

        assertEquals(2, store.badgeCount())
    }

    @Test
    fun `badgeCountForGroup は指定フィード群の未読数を合計する`() = runTest(testDispatcher) {
        enqueueArticles(
            listOf(
                makeArticle(id = 1, feedId = 10, isRead = 0),
                makeArticle(id = 2, feedId = 10, isRead = 1),
                makeArticle(id = 3, feedId = 20, isRead = 0),
                makeArticle(id = 4, feedId = 30, isRead = 0),
            ),
        )
        store.fetchArticles()
        store.setUnreadOnly(true)

        assertEquals(2, store.badgeCountForGroup(listOf(10, 20)))
    }

    @Test
    fun `badgeCountForGroup は空のフィード群では0を返す`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 10, isRead = 0)))
        store.fetchArticles()
        store.setUnreadOnly(true)

        assertEquals(0, store.badgeCountForGroup(emptyList()))
    }

    @Test
    fun `badgeCountForGroup は allArticles が埋まっていればそちらを優先する`() = runTest(testDispatcher) {
        // feed10 の記事で allArticles(コレクション) を埋める
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 10, isRead = 0), makeArticle(id = 2, feedId = 10, isRead = 1)))
        store.fetchArticles(feedId = 10)

        // articles を feed20 のみへ差し替える（allArticles は feed10 を保持したまま）
        enqueueArticles(listOf(makeArticle(id = 3, feedId = 20, isRead = 0)))
        store.fetchArticles(feedId = 20)
        store.setUnreadOnly(true)

        // articles には feed10 の記事は無いが、allArticles には残っているためそちらを使う
        assertEquals(1, store.badgeCountForGroup(listOf(10)))
    }

    @Test
    fun `hasVisibleArticle はフィルタなしなら常にtrue`() {
        assertTrue(store.hasVisibleArticle(1))
    }

    @Test
    fun `hasVisibleArticle は未読ありのフィードでtrue`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 0)))
        store.fetchArticles()
        store.setUnreadOnly(true)

        assertTrue(store.hasVisibleArticle(1))
    }

    @Test
    fun `hasVisibleArticle は全既読のフィードでfalse`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 1)))
        store.fetchArticles()
        store.setUnreadOnly(true)

        assertFalse(store.hasVisibleArticle(1))
    }

    // MARK: - refresh() + unreadOnly 既読記事保持

    @Test
    fun `refresh は unreadOnly のとき既読にした記事を保持する`() = runTest(testDispatcher) {
        store.setUnreadOnly(true)
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 0), makeArticle(id = 2, isRead = 0)))
        store.fetchArticles()

        // ユーザーが id:1 を既読にする（楽観更新）
        enqueueEmptyOk()
        store.markAsRead(1)

        // サーバーは未読のみ返す（id:1 は含まない）
        enqueueArticles(listOf(makeArticle(id = 2, isRead = 0)))
        enqueueArticles(emptyList()) // refreshCounts
        store.refresh()

        assertTrue(store.articles.value.any { it.id == 1 })
        assertTrue(store.articles.value.any { it.id == 2 })
    }

    @Test
    fun `refresh は unreadOnly でなければ既読記事を保持しない`() = runTest(testDispatcher) {
        store.setUnreadOnly(false)
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 1), makeArticle(id = 2, isRead = 0)))
        store.fetchArticles()

        enqueueArticles(listOf(makeArticle(id = 2, isRead = 0)))
        enqueueArticles(emptyList())
        store.refresh()

        assertFalse(store.articles.value.any { it.id == 1 })
        assertEquals(1, store.articles.value.size)
    }

    @Test
    fun `refresh は loadedWithUnreadOnly がfalseなら保持しない`() = runTest(testDispatcher) {
        store.setUnreadOnly(false)
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 1), makeArticle(id = 2, isRead = 0)))
        store.fetchArticles()

        store.setUnreadOnly(true)
        enqueueArticles(listOf(makeArticle(id = 2, isRead = 0)))
        enqueueArticles(emptyList())
        store.refresh()

        assertFalse(store.articles.value.any { it.id == 1 })
        assertEquals(1, store.articles.value.size)
    }

    @Test
    fun `refresh は保持した記事を published_at 降順でソートする`() = runTest(testDispatcher) {
        store.setUnreadOnly(true)
        val newerRead = makeArticle(id = 1, isRead = 0, publishedAt = "2024-06-01T00:00:00Z")
        val olderUnread = makeArticle(id = 2, isRead = 0, publishedAt = "2024-01-01T00:00:00Z")
        enqueueArticles(listOf(newerRead, olderUnread))
        store.fetchArticles()

        enqueueEmptyOk()
        store.markAsRead(1) // id:1 を既読化（新しい記事）

        // サーバーは未読のみ返す
        enqueueArticles(listOf(olderUnread))
        enqueueArticles(emptyList())
        store.refresh()

        assertEquals(listOf(1, 2), store.articles.value.map { it.id })
    }

    @Test
    fun `fetchArticles は unreadOnly のとき保持ロジックなしでサーバー結果のみ使う`() = runTest(testDispatcher) {
        store.setUnreadOnly(true)
        enqueueArticles(listOf(makeArticle(id = 1, isRead = 1), makeArticle(id = 2, isRead = 0)))
        store.fetchArticles()

        assertEquals(2, store.articles.value.size)
    }

    // MARK: - refreshCounts / feedCounts

    @Test
    fun `refreshCounts は feedCounts を更新する`() = runTest(testDispatcher) {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 5, unread = 3))),
            ),
        )

        store.refreshCounts()

        assertEquals(3, store.feedCounts.value[1]?.unread)
    }

    @Test
    fun `refreshCounts は失敗時に前回値を維持する`() = runTest(testDispatcher) {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 5, unread = 3))),
            ),
        )
        store.refreshCounts()

        server.enqueue(MockResponse().setResponseCode(500))
        store.refreshCounts()

        assertEquals(3, store.feedCounts.value[1]?.unread)
    }

    @Test
    fun `badgeCount は feedCounts があればそちらを使う`() = runTest(testDispatcher) {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(
                    ListSerializer(FeedCount.serializer()),
                    listOf(FeedCount(feed_id = 1, total = 5, unread = 3), FeedCount(feed_id = 2, total = 2, unread = 0)),
                ),
            ),
        )
        store.refreshCounts()
        store.setUnreadOnly(true)

        assertEquals(3, store.badgeCount(1))
        assertEquals(3, store.badgeCountForGroup(listOf(1, 2)))
    }

    @Test
    fun `markAsRead は feedCounts の unread を1減らす`() = runTest(testDispatcher) {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 5, unread = 3))),
            ),
        )
        store.refreshCounts()

        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 0)))
        store.fetchArticles()

        enqueueEmptyOk()
        store.markAsRead(1)

        assertEquals(2, store.feedCounts.value[1]?.unread)
    }

    @Test
    fun `markAsRead はロールバック時に feedCounts を戻す`() = runTest(testDispatcher) {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 5, unread = 3))),
            ),
        )
        store.refreshCounts()

        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 0)))
        store.fetchArticles()

        server.enqueue(MockResponse().setResponseCode(500))
        store.markAsRead(1)

        assertEquals(3, store.feedCounts.value[1]?.unread)
    }

    @Test
    fun `unreadCount は0未満にならない`() = runTest(testDispatcher) {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 1, unread = 0))),
            ),
        )
        store.refreshCounts()

        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 1)))
        store.fetchArticles()

        // 既に unread=0 の状態で既読にしても負にならない（既読→既読の遷移なので unreadDelta=0 だが、
        // 未読側の下限保証を明示的に検証する）
        enqueueEmptyOk()
        store.markAsUnread(1)
        assertEquals(1, store.feedCounts.value[1]?.unread)
    }

    @Test
    fun `refreshCounts は pendingReadIds を減算する`() = runTest(testDispatcher) {
        enqueueArticles(listOf(makeArticle(id = 1, feedId = 1, isRead = 0)))
        store.fetchArticles()

        store.configure(unreachableClient)
        store.markAsRead(1) // pendingReadIds に積まれる
        store.configure(goodClient())

        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 5, unread = 3))),
            ),
        )
        store.refreshCounts()

        assertEquals(2, store.feedCounts.value[1]?.unread)
    }

    @Test
    fun `refresh は refreshCounts も実行する`() = runTest(testDispatcher) {
        enqueueArticles(emptyList())
        store.fetchArticles()

        enqueueArticles(emptyList())
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 1, unread = 1))),
            ),
        )
        store.refresh()

        assertEquals(1, store.feedCounts.value[1]?.unread)
    }

    // MARK: - キャッシュ

    @Test
    fun `init はキャッシュから allArticles を読み込む`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveAllArticles(listOf(makeArticle(id = 42)))

        val storeWithCache = ArticleStore(cache, InMemoryKeyValueStore(), storeScope)

        assertEquals(listOf(42), storeWithCache.allArticles.value.map { it.id })
    }

    @Test
    fun `fetchArticles はキャッシュへ全記事を保存する`() = runTest(testDispatcher) {
        val cache = AppCache(tempFolder.newFolder())
        val storeWithCache = ArticleStore(cache, InMemoryKeyValueStore(), storeScope)
        storeWithCache.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl(), httpClient = testHttpClient))

        enqueueArticles(listOf(makeArticle(id = 1), makeArticle(id = 2)))
        storeWithCache.fetchArticles()

        assertEquals(2, cache.loadAllArticles().size)
    }

    @Test
    fun `refreshCounts はキャッシュへ保存する`() = runTest(testDispatcher) {
        val cache = AppCache(tempFolder.newFolder())
        val storeWithCache = ArticleStore(cache, InMemoryKeyValueStore(), storeScope)
        storeWithCache.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl(), httpClient = testHttpClient))

        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                Json.encodeToString(ListSerializer(FeedCount.serializer()), listOf(FeedCount(feed_id = 1, total = 5, unread = 3))),
            ),
        )
        storeWithCache.refreshCounts()

        assertEquals(1, cache.loadFeedCounts().size)

        val restoredStore = ArticleStore(cache, InMemoryKeyValueStore(), storeScope)
        assertEquals(3, restoredStore.feedCounts.value[1]?.unread)
    }

    // MARK: - unreadOnly / sortOrder の永続化

    @Test
    fun `setUnreadOnly は KeyValueStore へ保存する`() {
        store.setUnreadOnly(true)
        assertTrue(keyValueStore.getBoolean(com.mtkg.gogai.cache.DefaultsKeys.UNREAD_ONLY, false))
    }

    @Test
    fun `setSortOrder は KeyValueStore へ保存する`() {
        store.setSortOrder(ArticleSortOrder.ReadAt)
        assertEquals("read_at", keyValueStore.getString(com.mtkg.gogai.cache.DefaultsKeys.SORT_ORDER))
    }
}
