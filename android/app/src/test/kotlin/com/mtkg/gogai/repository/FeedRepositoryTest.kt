package com.mtkg.gogai.repository

import com.mtkg.gogai.model.FieldUpdate
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private val sampleFeedJson = """
    {"id":1,"url":"https://example.com/feed","title":"Example","group_id":2,"created_at":"2026-01-01T00:00:00Z","display_order":0}
""".trimIndent()

class FeedRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: FeedRepository

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        val client = ApiClient(baseUrl = server.url("/").toString().toHttpUrl())
        repository = FeedRepository(client)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetchAll は GET api feeds を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("[$sampleFeedJson]"))
        val feeds = repository.fetchAll()
        assertEquals(1, feeds.size)
        assertEquals("GET", server.takeRequest().method)
    }

    @Test
    fun `create は groupId が null なら省略する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleFeedJson))
        repository.create(url = "https://example.com/feed")
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("https://example.com/feed", body["url"]?.jsonPrimitive?.content)
        assertFalse(body.containsKey("groupId"))
    }

    @Test
    fun `create は groupId 指定時に含める`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleFeedJson))
        repository.create(url = "https://example.com/feed", groupId = 5)
        val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertEquals(5, body["groupId"]?.jsonPrimitive?.int)
    }

    @Test
    fun `update は groupId Keep でキーを省略する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleFeedJson))
        repository.update(id = 1, title = "New Title")
        val recorded = server.takeRequest()
        assertEquals("PUT", recorded.method)
        assertEquals("/api/feeds/1", recorded.path)
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("New Title", body["title"]?.jsonPrimitive?.content)
        assertFalse(body.containsKey("groupId"))
    }

    @Test
    fun `update は groupId Clear で明示的な null を送る`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleFeedJson))
        repository.update(id = 1, groupId = FieldUpdate.Clear)
        val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertTrue(body.containsKey("groupId"))
        assertEquals(JsonNull, body["groupId"])
    }

    @Test
    fun `update は groupId Set で値を送る`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleFeedJson))
        repository.update(id = 1, groupId = FieldUpdate.Set(9))
        val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertEquals(9, body["groupId"]?.jsonPrimitive?.int)
    }

    @Test
    fun `delete は DELETE api feeds id を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.delete(id = 3)
        val recorded = server.takeRequest()
        assertEquals("DELETE", recorded.method)
        assertEquals("/api/feeds/3", recorded.path)
    }

    @Test
    fun `reorder は PATCH body に ids を含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.reorder(listOf(3, 1, 2))
        val recorded = server.takeRequest()
        assertEquals("PATCH", recorded.method)
        assertEquals("/api/feeds/reorder", recorded.path)
        assertEquals("""{"ids":[3,1,2]}""", recorded.body.readUtf8())
    }
}
