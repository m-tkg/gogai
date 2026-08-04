package com.mtkg.gogai.store

import com.mtkg.gogai.cache.InMemorySecretStore
import com.mtkg.gogai.cache.SecretStore
import com.mtkg.gogai.model.Settings
import com.mtkg.gogai.model.UpdateCheck
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class SettingsStoreTest {
    private lateinit var server: MockWebServer
    private lateinit var secretStore: InMemorySecretStore
    private lateinit var store: SettingsStore

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        secretStore = InMemorySecretStore()
        store = SettingsStore()
        store.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()), secretStore)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun enqueue(code: Int, body: String = "") {
        server.enqueue(MockResponse().setResponseCode(code).setBody(body))
    }

    @Test
    fun `fetchSettings は settings を更新する`() = runTest {
        enqueue(200, Json.encodeToString(Settings.serializer(), Settings(retention_days = 90)))

        store.fetchSettings()

        assertEquals(90, store.settings.value?.retention_days)
        assertNull(store.error.value)
    }

    @Test
    fun `fetchSettings は失敗時に error をセットする`() = runTest {
        enqueue(500)

        store.fetchSettings()

        assertNotNull(store.error.value)
    }

    @Test
    fun `updateRetentionDays は settings を更新する`() = runTest {
        enqueue(200, Json.encodeToString(Settings.serializer(), Settings(retention_days = 30)))

        store.updateRetentionDays(30)

        assertEquals(30, store.settings.value?.retention_days)
    }

    @Test
    fun `checkUpdate は updateCheck を更新する`() = runTest {
        enqueue(200, Json.encodeToString(UpdateCheck.serializer(), UpdateCheck(local = "a", remote = "b", hasUpdate = true)))

        store.checkUpdate()

        assertEquals(true, store.updateCheck.value?.hasUpdate)
    }

    @Test
    fun `restart は output を返す`() = runTest {
        enqueue(200, """{"output":"restarted"}""")

        val output = store.restart()

        assertEquals("restarted", output)
    }

    @Test
    fun `checkUpdate は ADMIN_SECRET 設定時にヘッダーを送る`() = runTest {
        secretStore.set(SecretStore.ADMIN_SECRET, "s3cret")
        enqueue(200, Json.encodeToString(UpdateCheck.serializer(), UpdateCheck(local = "a", remote = "b", hasUpdate = false)))

        store.checkUpdate()

        val recorded = server.takeRequest()
        assertEquals("s3cret", recorded.getHeader("X-Admin-Secret"))
    }

    @Test
    fun `isLoading は checkUpdate完了後にfalseへ戻る`() = runTest {
        enqueue(200, Json.encodeToString(UpdateCheck.serializer(), UpdateCheck(local = "a", remote = "b", hasUpdate = false)))

        store.checkUpdate()

        assertEquals(false, store.isLoading.value)
    }
}
