package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.RefreshResult
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class FeedStoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var server: MockWebServer
    private lateinit var store: FeedStore

    private fun makeFeed(id: Int = 1, groupId: Int? = null, displayOrder: Int = 0) = Feed(
        id = id,
        url = "https://example.com/feed.xml",
        title = "Example $id",
        group_id = groupId,
        created_at = "2024-01-01T00:00:00Z",
        display_order = displayOrder,
    )

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = FeedStore(AppCache(tempFolder.newFolder()))
        store.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun enqueue(code: Int, body: String = "") {
        server.enqueue(MockResponse().setResponseCode(code).setBody(body))
    }

    @Test
    fun `fetchFeeds は feeds を更新する`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Feed.serializer()), listOf(makeFeed(id = 1), makeFeed(id = 2))))

        store.fetchFeeds()

        assertEquals(2, store.feeds.value.size)
    }

    @Test
    fun `feeds groupId は該当グループのフィードのみ返す`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveFeeds(listOf(makeFeed(id = 1, groupId = 1), makeFeed(id = 2, groupId = 2), makeFeed(id = 3, groupId = 1)))
        val storeWithCache = FeedStore(cache)

        val filtered = storeWithCache.feeds(1)

        assertEquals(2, filtered.size)
        assertTrue(filtered.all { it.group_id == 1 })
    }

    @Test
    fun `feeds null は全フィードを返す`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveFeeds(listOf(makeFeed(id = 1, groupId = 1), makeFeed(id = 2, groupId = null)))
        val storeWithCache = FeedStore(cache)

        assertEquals(2, storeWithCache.feeds(null).size)
    }

    @Test
    fun `deleteFeed は feeds から削除する`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Feed.serializer()), listOf(makeFeed(id = 1), makeFeed(id = 2))))
        store.fetchFeeds()

        enqueue(200)
        store.deleteFeed(1)

        assertEquals(1, store.feeds.value.size)
        assertEquals(2, store.feeds.value[0].id)
    }

    @Test
    fun `refreshAll は onRefreshComplete を呼ぶ`() = runTest {
        var completionCalled = false
        store.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()), onRefreshComplete = { completionCalled = true })
        enqueue(200, Json.encodeToString(RefreshResult.serializer(), RefreshResult(refreshed = 3, failed = 0)))

        store.refreshAll()

        assertTrue(completionCalled)
    }

    // MARK: - reorderFeeds

    @Test
    fun `reorderFeeds はローカル順序を更新する`() = runTest {
        enqueue(
            200,
            Json.encodeToString(
                ListSerializer(Feed.serializer()),
                listOf(
                    makeFeed(id = 1, groupId = 1, displayOrder = 0),
                    makeFeed(id = 2, groupId = 1, displayOrder = 1),
                    makeFeed(id = 3, groupId = 1, displayOrder = 2),
                ),
            ),
        )
        store.fetchFeeds()

        enqueue(204)
        store.reorderFeeds(from = 0, to = 3, groupId = 1)

        val groupFeeds = store.feeds(1)
        assertEquals(2, groupFeeds[0].id)
        assertEquals(3, groupFeeds[1].id)
        assertEquals(1, groupFeeds[2].id)
    }

    // MARK: - isRefreshing

    @Test
    fun `isRefreshing は初期値false`() {
        assertFalse(store.isRefreshing.value)
    }

    @Test
    fun `isRefreshing は refreshAll成功後にfalseへ戻る`() = runTest {
        enqueue(200, Json.encodeToString(RefreshResult.serializer(), RefreshResult(refreshed = 1, failed = 0)))

        store.refreshAll()

        assertFalse(store.isRefreshing.value)
    }

    @Test
    fun `isRefreshing は refreshAll失敗後もfalseへ戻る`() = runTest {
        enqueue(500)

        try {
            store.refreshAll()
        } catch (e: Exception) {
            // 期待通り: 失敗を呼び出し元へ伝播する
        }

        assertFalse(store.isRefreshing.value)
    }

    // MARK: - キャッシュ

    @Test
    fun `init はキャッシュからフィードを読み込む`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveFeeds(listOf(makeFeed(id = 42)))

        val storeWithCache = FeedStore(cache)

        assertEquals(1, storeWithCache.feeds.value.size)
        assertEquals(42, storeWithCache.feeds.value[0].id)
    }

    @Test
    fun `fetchFeeds はキャッシュへ保存する`() = runTest {
        val cache = AppCache(tempFolder.newFolder())
        val storeWithCache = FeedStore(cache)
        storeWithCache.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))

        enqueue(200, Json.encodeToString(ListSerializer(Feed.serializer()), listOf(makeFeed(id = 1), makeFeed(id = 2))))
        storeWithCache.fetchFeeds()

        assertEquals(2, cache.loadFeeds().size)
    }
}
