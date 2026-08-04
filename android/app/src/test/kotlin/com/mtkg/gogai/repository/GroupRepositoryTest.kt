package com.mtkg.gogai.repository

import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test

private val sampleGroupJson = """
    {"id":1,"name":"Tech","is_secret":0,"created_at":"2026-01-01T00:00:00Z","display_order":0}
""".trimIndent()

class GroupRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: GroupRepository

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        repository = GroupRepository(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `create は body に name のみ含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleGroupJson))
        repository.create("Tech")
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("""{"name":"Tech"}""", recorded.body.readUtf8())
    }

    @Test
    fun `update は isSecret null なら name のみ送る`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleGroupJson))
        repository.update(id = 1, name = "Tech2")
        val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertEquals("Tech2", body["name"]?.jsonPrimitive?.content)
        assertFalse(body.containsKey("is_secret"))
    }

    @Test
    fun `update は isSecret 指定時に is_secret を含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleGroupJson))
        repository.update(id = 1, name = "Tech2", isSecret = 1)
        val recorded = server.takeRequest()
        assertEquals("/api/groups/1", recorded.path)
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals(1, body["is_secret"]?.jsonPrimitive?.int)
    }

    @Test
    fun `reorder は PATCH body に ids を含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.reorder(listOf(2, 1))
        val recorded = server.takeRequest()
        assertEquals("PATCH", recorded.method)
        assertEquals("/api/groups/reorder", recorded.path)
        assertEquals("""{"ids":[2,1]}""", recorded.body.readUtf8())
    }

    @Test
    fun `refresh は POST api groups id refresh を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"refreshed":1,"failed":0}"""))
        val result = repository.refresh(1)
        assertEquals(1, result.refreshed)
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/api/groups/1/refresh", recorded.path)
    }
}
