package com.mtkg.gogai.network

import java.io.IOException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

@Serializable
private data class Dummy(val id: Int, val name: String)

class ApiClientTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun client(onNetworkFailure: (() -> Unit)? = null): ApiClient =
        ApiClient(baseUrl = server.url("/").toString().toHttpUrl(), onNetworkFailure = onNetworkFailure)

    @Test
    fun `200 応答は JSON デコードに成功する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":1,"name":"foo"}"""))
        val result = client().send(Endpoint.get("/api/dummy"), Dummy.serializer())
        assertEquals(Dummy(1, "foo"), result)
    }

    @Test
    fun `非 2xx は ApiException Http を投げる`() = runTest {
        server.enqueue(MockResponse().setResponseCode(404).setBody("""{"error":"Not found"}"""))
        try {
            client().send(Endpoint.get("/api/dummy"), Dummy.serializer())
            fail("例外が投げられるべき")
        } catch (e: ApiException.Http) {
            assertEquals(404, e.statusCode)
            assertEquals("HTTPエラー 404: Not found", e.message)
        }
    }

    @Test
    fun `接続失敗は IOException を rethrow し onNetworkFailure を呼ぶ`() = runTest {
        val url = server.url("/").toString().toHttpUrl()
        server.shutdown()
        var notified = false
        try {
            ApiClient(baseUrl = url, onNetworkFailure = { notified = true })
                .send(Endpoint.get("/api/dummy"), Dummy.serializer())
            fail("例外が投げられるべき")
        } catch (e: IOException) {
            // expected
        }
        assertTrue(notified)
    }

    @Test
    fun `デコード失敗は ApiException Decoding を投げる`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""not json"""))
        try {
            client().send(Endpoint.get("/api/dummy"), Dummy.serializer())
            fail("例外が投げられるべき")
        } catch (e: ApiException.Decoding) {
            // expected
        }
    }

    @Test
    fun `非 2xx では onNetworkFailure は呼ばれない`() = runTest {
        server.enqueue(MockResponse().setResponseCode(500).setBody("""{"error":"boom"}"""))
        var notified = false
        try {
            client { notified = true }.send(Endpoint.get("/api/dummy"), Dummy.serializer())
            fail("例外が投げられるべき")
        } catch (e: ApiException.Http) {
            // expected
        }
        assertFalse(notified)
    }

    @Test
    fun `クエリ・ヘッダ・メソッド・ボディが正しくリクエストに載る`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"id":2,"name":"bar"}"""))
        client().send(
            Endpoint.put(
                "/api/dummy/2",
                body = """{"name":"bar"}""",
            ).let { it.copy(queryItems = listOf("x" to "1"), headers = mapOf("X-Test" to "yes")) },
            Dummy.serializer(),
        )
        val recorded = server.takeRequest()
        assertEquals("PUT", recorded.method)
        assertEquals("/api/dummy/2?x=1", recorded.path)
        assertEquals("yes", recorded.getHeader("X-Test"))
        assertEquals("""{"name":"bar"}""", recorded.body.readUtf8())
    }
}
