package com.mtkg.gogai.repository

import com.mtkg.gogai.model.ArticleFilter
import com.mtkg.gogai.model.ArticleSortOrder
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

private val sampleArticleJson = """
    {"id":1,"feed_id":2,"guid":"g1","title":"T","is_read":0,"created_at":"2026-01-01T00:00:00Z"}
""".trimIndent()

class ArticleRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: ArticleRepository

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        repository = ArticleRepository(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetchAll はデフォルトの limit offset sortBy を付与する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("[$sampleArticleJson]"))
        repository.fetchAll()
        val recorded = server.takeRequest()
        assertEquals("/api/articles?limit=1000&offset=0&sortBy=published_at", recorded.path)
    }

    @Test
    fun `fetchAll は feedId unreadOnly includeSecret 指定時にクエリへ含める`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("[$sampleArticleJson]"))
        repository.fetchAll(
            feedId = 7,
            filter = ArticleFilter.Unread,
            sortOrder = ArticleSortOrder.ReadAt,
            includeSecret = true,
        )
        val recorded = server.takeRequest()
        assertEquals(
            "/api/articles?limit=1000&offset=0&sortBy=read_at&feedId=7&unreadOnly=true&includeSecret=true",
            recorded.path,
        )
    }

    @Test
    fun `fetchAll は liked フィルターで likedOnly を付与する`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("[$sampleArticleJson]"))
        repository.fetchAll(filter = ArticleFilter.Liked)
        val recorded = server.takeRequest()
        assertEquals("/api/articles?limit=1000&offset=0&sortBy=published_at&likedOnly=true", recorded.path)
    }

    @Test
    fun `like は POST api articles id like を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.like(id = 5)
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/api/articles/5/like", recorded.path)
    }

    @Test
    fun `unlike は POST api articles id unlike を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.unlike(id = 5)
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/api/articles/5/unlike", recorded.path)
    }

    @Test
    fun `markAsRead は POST api articles id read を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.markAsRead(id = 5)
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/api/articles/5/read", recorded.path)
    }

    @Test
    fun `markAsUnread は POST api articles id unread を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody(""))
        repository.markAsUnread(id = 5)
        val recorded = server.takeRequest()
        assertEquals("/api/articles/5/unread", recorded.path)
    }

    @Test
    fun `fetchCounts は GET api articles counts を叩く`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""[{"feed_id":1,"total":2,"unread":1,"liked":1}]"""))
        val counts = repository.fetchCounts()
        assertEquals(1, counts.size)
        assertEquals(1, counts[0].liked)
        val recorded = server.takeRequest()
        assertEquals("/api/articles/counts", recorded.path)
    }
}
