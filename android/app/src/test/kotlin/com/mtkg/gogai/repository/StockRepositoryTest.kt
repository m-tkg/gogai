package com.mtkg.gogai.repository

import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private val sampleStockJson = """
    {"id":1,"url":"https://example.com/a","title":"Title","source":"Group",
     "category_id":1,"category_name":"Default","has_translation":false,
     "stocked_at":"2026-01-01T00:00:00Z","created_at":"2026-01-01T00:00:00Z"}
""".trimIndent()

class StockRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: StockRepository

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        repository = StockRepository(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetchAll は categoryId 指定時に category_id クエリを付与する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("[$sampleStockJson]"))
        repository.fetchAll(categoryId = 3)
        val recorded = server.takeRequest()
        assertEquals("/api/stocks?category_id=3", recorded.path)
    }

    @Test
    fun `create は null フィールドを JSON から省略する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleStockJson))
        repository.create(url = "https://example.com/a")
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("https://example.com/a", body["url"]?.jsonPrimitive?.content)
        assertFalse(body.containsKey("title"))
        assertFalse(body.containsKey("source"))
        assertFalse(body.containsKey("category"))
    }

    @Test
    fun `create は指定したフィールドをすべて含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(sampleStockJson))
        repository.create(url = "https://example.com/a", title = "T", source = "S", category = "C")
        val body = Json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertEquals("T", body["title"]?.jsonPrimitive?.content)
        assertEquals("S", body["source"]?.jsonPrimitive?.content)
        assertEquals("C", body["category"]?.jsonPrimitive?.content)
    }

    @Test
    fun `saveSummary は PUT api stocks id summary を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.saveSummary(id = 1, summary = "要約です")
        val recorded = server.takeRequest()
        assertEquals("PUT", recorded.method)
        assertEquals("/api/stocks/1/summary", recorded.path)
        assertEquals("""{"summary":"要約です"}""", recorded.body.readUtf8())
    }

    @Test
    fun `lookup は該当なしで null を返す`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"stock":null}"""))
        val result = repository.lookup("https://example.com/none")
        assertNull(result)
        val recorded = server.takeRequest()
        assertEquals("/api/stocks/lookup?url=https%3A%2F%2Fexample.com%2Fnone", recorded.path)
    }

    @Test
    fun `lookup は該当ありで Stock を返す`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"stock":$sampleStockJson}"""))
        val result = repository.lookup("https://example.com/a")
        assertTrue(result != null)
        assertEquals(1, result?.id)
    }

    @Test
    fun `reorderCategories は PATCH body に ids を含む`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.reorderCategories(listOf(4, 5))
        val recorded = server.takeRequest()
        assertEquals("PATCH", recorded.method)
        assertEquals("/api/stock-categories/reorder", recorded.path)
        assertEquals("""{"ids":[4,5]}""", recorded.body.readUtf8())
    }
}
