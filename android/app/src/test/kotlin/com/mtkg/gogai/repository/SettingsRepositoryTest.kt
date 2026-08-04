package com.mtkg.gogai.repository

import com.mtkg.gogai.cache.InMemorySecretStore
import com.mtkg.gogai.cache.SecretStore
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class SettingsRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var secretStore: InMemorySecretStore
    private lateinit var repository: SettingsRepository

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        secretStore = InMemorySecretStore()
        repository = SettingsRepository(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()), secretStore)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `update は PUT body に retention_days を含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"retention_days":90}"""))
        val result = repository.update(retentionDays = 90)
        assertEquals(90, result.retention_days)
        val recorded = server.takeRequest()
        assertEquals("PUT", recorded.method)
        assertEquals("/api/settings", recorded.path)
        assertEquals("""{"retention_days":90}""", recorded.body.readUtf8())
    }

    @Test
    fun `ADMIN_SECRET 未設定なら adminHeaders は空`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"local":"a","remote":"b","hasUpdate":true}"""))
        repository.checkUpdate()
        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("X-Admin-Secret"))
    }

    @Test
    fun `ADMIN_SECRET 設定時は X-Admin-Secret ヘッダーを送る`() = runTest {
        secretStore.set(SecretStore.ADMIN_SECRET, "s3cret")
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"local":"a","remote":"b","hasUpdate":false}"""))
        repository.checkUpdate()
        val recorded = server.takeRequest()
        assertEquals("s3cret", recorded.getHeader("X-Admin-Secret"))
        assertEquals("/api/admin/update-check", recorded.path)
    }

    @Test
    fun `restart は output を返す`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"output":"restarted"}"""))
        val output = repository.restart()
        assertEquals("restarted", output)
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/api/admin/restart", recorded.path)
    }
}
