package com.mtkg.gogai.network

import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.InMemoryKeyValueStore
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class ServerUrlManagerTest {
    private lateinit var server: MockWebServer
    private val httpClient = OkHttpClient()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun manager(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        gistApiBaseUrl: String = server.url("/").toString(),
        failureDebounceMillis: Long = 30_000,
        nowMillis: () -> Long = System::currentTimeMillis,
    ) = ServerUrlManager(store, httpClient, gistApiBaseUrl, failureDebounceMillis, nowMillis)

    @Test
    fun `非 gist URL は即座に解決される`() = runTest {
        val store = InMemoryKeyValueStore()
        val target = manager(store)
        target.setServerUrl("https://myserver.example.com")

        target.resolve()

        assertEquals("https://myserver.example.com/".toHttpUrl(), target.resolvedUrl.value)
    }

    @Test
    fun `gist URL は GitHub API 経由で解決され resolvedUrl とキャッシュが更新される`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"files":{"tunnel.txt":{"content":"https://xxxx.trycloudflare.com\n"}}}"""
            )
        )
        val store = InMemoryKeyValueStore()
        val target = manager(store)
        target.setServerUrl("https://gist.github.com/someone/abcdef123")

        target.resolve()

        assertEquals("https://xxxx.trycloudflare.com/".toHttpUrl(), target.resolvedUrl.value)
        assertEquals("https://xxxx.trycloudflare.com/", store.getString(DefaultsKeys.RESOLVED_SERVER_URL))
        val recorded = server.takeRequest()
        assertEquals("/gists/abcdef123", recorded.path)
    }

    @Test
    fun `gist レスポンスの content が URL として無効なら resolvedUrl を維持する`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"files":{"tunnel.txt":{"content":"not-a-valid-url"}}}"""
            )
        )
        val store = InMemoryKeyValueStore()
        val target = manager(store)
        target.setServerUrl("https://gist.github.com/someone/abcdef123")

        target.resolve()

        assertNull(target.resolvedUrl.value)
        assertNull(store.getString(DefaultsKeys.RESOLVED_SERVER_URL))
    }

    @Test
    fun `reportFailure は デバウンス期間内なら連続呼び出しで resolve を1回しか実行しない`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"files":{"tunnel.txt":{"content":"https://first.example.com"}}}"""
            )
        )
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"files":{"tunnel.txt":{"content":"https://second.example.com"}}}"""
            )
        )
        var now = 0L
        val store = InMemoryKeyValueStore()
        val target = manager(store, nowMillis = { now })
        target.setServerUrl("https://gist.github.com/someone/abcdef123")

        target.reportFailure()
        assertEquals(1, server.requestCount)

        // デバウンス期間内（30秒未満）なので resolve は実行されない
        now += 10_000
        target.reportFailure()
        assertEquals(1, server.requestCount)

        // デバウンス期間を超えたので resolve が実行される
        now += 25_000
        target.reportFailure()
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `init はキャッシュ済み resolvedUrl を gist URL 保存時のみ復元する`() {
        val gistStore = InMemoryKeyValueStore().apply {
            putString(DefaultsKeys.SERVER_URL, "https://gist.github.com/someone/abcdef123")
            putString(DefaultsKeys.RESOLVED_SERVER_URL, "https://cached.example.com")
        }
        val gistManager = manager(gistStore)
        assertEquals("https://cached.example.com".toHttpUrl(), gistManager.resolvedUrl.value)

        val nonGistStore = InMemoryKeyValueStore().apply {
            putString(DefaultsKeys.SERVER_URL, "https://myserver.example.com")
            putString(DefaultsKeys.RESOLVED_SERVER_URL, "https://cached.example.com")
        }
        val nonGistManager = manager(nonGistStore)
        assertNull(nonGistManager.resolvedUrl.value)
    }
}
