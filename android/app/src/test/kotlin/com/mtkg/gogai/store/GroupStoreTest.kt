package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.Group
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
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

class GroupStoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var server: MockWebServer
    private lateinit var store: GroupStore

    private fun makeGroup(id: Int = 1, name: String = "Tech", isSecret: Int = 0, displayOrder: Int = 0) =
        Group(id = id, name = name, is_secret = isSecret, created_at = "2024-01-01T00:00:00Z", display_order = displayOrder)

    private fun makeFeed(id: Int, groupId: Int?) = Feed(
        id = id,
        url = "https://example.com/$id",
        title = "Feed $id",
        group_id = groupId,
        created_at = "2024-01-01T00:00:00Z",
        display_order = 0,
    )

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = GroupStore(AppCache(tempFolder.newFolder()))
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
    fun `fetchGroups は groups を更新する`() = runTest {
        val expected = listOf(makeGroup(id = 1, name = "Tech"), makeGroup(id = 2, name = "News"))
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), expected))

        store.fetchGroups()

        assertEquals(2, store.groups.value.size)
        assertEquals("Tech", store.groups.value[0].name)
        assertNull(store.error.value)
    }

    @Test
    fun `fetchGroups は失敗時に error をセットする`() = runTest {
        enqueue(500)

        store.fetchGroups()

        assertNotNull(store.error.value)
    }

    @Test
    fun `createGroup は groups へ追加する`() = runTest {
        val newGroup = makeGroup(id = 5, name = "Sports")
        enqueue(200, Json.encodeToString(Group.serializer(), newGroup))

        store.createGroup("Sports")

        assertEquals(1, store.groups.value.size)
        assertEquals("Sports", store.groups.value[0].name)
    }

    @Test
    fun `deleteGroup は groups から削除する`() = runTest {
        // 事前に一覧をセットする代わりに fetchGroups で投入する
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1), makeGroup(id = 2))))
        store.fetchGroups()

        enqueue(200)
        store.deleteGroup(1)

        assertEquals(1, store.groups.value.size)
        assertEquals(2, store.groups.value[0].id)
    }

    @Test
    fun `updateGroup は groups 内の該当要素を差し替える`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1, name = "Old"))))
        store.fetchGroups()

        val updated = makeGroup(id = 1, name = "New")
        enqueue(200, Json.encodeToString(Group.serializer(), updated))
        store.updateGroup(id = 1, name = "New")

        assertEquals("New", store.groups.value[0].name)
    }

    // MARK: - showSecretGroups / visibleGroups

    @Test
    fun `visibleGroups は showSecretGroups がfalseならシークレットグループを隠す`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1, name = "Public"), makeGroup(id = 2, name = "Secret", isSecret = 1))))
        store.fetchGroups()
        store.setShowSecretGroups(false)

        assertEquals(1, store.visibleGroups.size)
        assertEquals("Public", store.visibleGroups[0].name)
    }

    @Test
    fun `visibleGroups は showSecretGroups がtrueならシークレットグループも表示する`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1, name = "Public"), makeGroup(id = 2, name = "Secret", isSecret = 1))))
        store.fetchGroups()
        store.setShowSecretGroups(true)

        assertEquals(2, store.visibleGroups.size)
    }

    @Test
    fun `showSecretGroups は初期値false`() {
        assertFalse(store.showSecretGroups.value)
    }

    @Test
    fun `resetSecretVisibility は showSecretGroups をfalseに戻す`() {
        store.setShowSecretGroups(true)
        store.resetSecretVisibility()
        assertFalse(store.showSecretGroups.value)
    }

    // MARK: - collapsedGroupIds / isExpanded / toggleExpanded

    @Test
    fun `isExpanded は初期値true`() {
        assertTrue(store.isExpanded(1))
        assertTrue(store.isExpanded(99))
    }

    @Test
    fun `toggleExpanded は展開済みグループを折りたたむ`() {
        store.toggleExpanded(1)
        assertFalse(store.isExpanded(1))
    }

    @Test
    fun `toggleExpanded は折りたたみ済みグループを展開する`() {
        store.toggleExpanded(1)
        store.toggleExpanded(1)
        assertTrue(store.isExpanded(1))
    }

    @Test
    fun `toggleExpanded は他のグループに影響しない`() {
        store.toggleExpanded(1)
        assertFalse(store.isExpanded(1))
        assertTrue(store.isExpanded(2))
    }

    @Test
    fun `deleteGroup は折りたたみ状態もクリアする`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1))))
        store.fetchGroups()
        store.toggleExpanded(1)
        assertFalse(store.isExpanded(1))

        enqueue(200)
        store.deleteGroup(1)

        assertTrue(store.isExpanded(1))
    }

    // MARK: - reorderGroups

    @Test
    fun `reorderGroups はローカル順序を更新する`() = runTest {
        enqueue(
            200,
            Json.encodeToString(
                ListSerializer(Group.serializer()),
                listOf(
                    makeGroup(id = 1, name = "A", displayOrder = 0),
                    makeGroup(id = 2, name = "B", displayOrder = 1),
                    makeGroup(id = 3, name = "C", displayOrder = 2),
                ),
            ),
        )
        store.fetchGroups()

        enqueue(204)
        store.reorderGroups(from = 0, to = 3)

        assertEquals(2, store.groups.value[0].id)
        assertEquals(3, store.groups.value[1].id)
        assertEquals(1, store.groups.value[2].id)
    }

    // MARK: - キャッシュ

    @Test
    fun `init はキャッシュからグループを読み込む`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveGroups(listOf(makeGroup(id = 42, name = "Cached Group")))

        val storeWithCache = GroupStore(cache)

        assertEquals(1, storeWithCache.groups.value.size)
        assertEquals(42, storeWithCache.groups.value[0].id)
    }

    @Test
    fun `fetchGroups はキャッシュへ保存する`() = runTest {
        val cache = AppCache(tempFolder.newFolder())
        val storeWithCache = GroupStore(cache)
        storeWithCache.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))

        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1), makeGroup(id = 2))))
        storeWithCache.fetchGroups()

        assertEquals(2, cache.loadGroups().size)
    }

    // MARK: - secretFeedIds

    @Test
    fun `secretFeedIds はシークレットグループ所属のフィードIDを返す`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1, isSecret = 0), makeGroup(id = 2, isSecret = 1))))
        store.fetchGroups()

        val feeds = listOf(makeFeed(id = 10, groupId = 1), makeFeed(id = 11, groupId = 2), makeFeed(id = 12, groupId = null))
        assertEquals(setOf(11), store.secretFeedIds(feeds))
    }

    @Test
    fun `secretFeedIds は showSecretGroups中は空集合を返す`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 2, isSecret = 1))))
        store.fetchGroups()
        store.setShowSecretGroups(true)

        val feeds = listOf(makeFeed(id = 11, groupId = 2))
        assertEquals(emptySet<Int>(), store.secretFeedIds(feeds))
    }

    @Test
    fun `secretFeedIds はシークレットグループがなければ空集合を返す`() = runTest {
        enqueue(200, Json.encodeToString(ListSerializer(Group.serializer()), listOf(makeGroup(id = 1, isSecret = 0))))
        store.fetchGroups()

        val feeds = listOf(makeFeed(id = 10, groupId = 1))
        assertEquals(emptySet<Int>(), store.secretFeedIds(feeds))
    }
}
