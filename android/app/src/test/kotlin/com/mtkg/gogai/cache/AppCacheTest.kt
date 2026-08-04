package com.mtkg.gogai.cache

import com.mtkg.gogai.model.Article
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.Group
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AppCacheTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun newCache(): AppCache = AppCache(tempFolder.newFolder())

    private val sampleArticle = Article(
        id = 1,
        feed_id = 2,
        guid = "g1",
        title = "T",
        is_read = 0,
        created_at = "2026-01-01T00:00:00Z",
    )

    private val sampleFeed = Feed(
        id = 1,
        url = "https://example.com/feed",
        created_at = "2026-01-01T00:00:00Z",
        display_order = 0,
    )

    private val sampleGroup = Group(
        id = 1,
        name = "Tech",
        is_secret = 0,
        created_at = "2026-01-01T00:00:00Z",
        display_order = 0,
    )

    @Test
    fun `保存したデータをラウンドトリップで読み込める`() {
        val cache = newCache()

        cache.saveAllArticles(listOf(sampleArticle))
        cache.saveFeeds(listOf(sampleFeed))
        cache.saveGroups(listOf(sampleGroup))

        assertEquals(listOf(sampleArticle), cache.loadAllArticles())
        assertEquals(listOf(sampleFeed), cache.loadFeeds())
        assertEquals(listOf(sampleGroup), cache.loadGroups())
    }

    @Test
    fun `未保存の場合は空リストを返す`() {
        val cache = newCache()
        assertEquals(emptyList<Article>(), cache.loadAllArticles())
        assertEquals(emptyList<Feed>(), cache.loadFeeds())
    }

    @Test
    fun `壊れた JSON はデコード失敗として扱われ空リストを返す`() {
        val baseDir = tempFolder.newFolder()
        val cache = AppCache(baseDir)
        val dir = File(baseDir, "gogai")
        dir.mkdirs()
        File(dir, "feeds.json").writeText("not json at all")

        assertEquals(emptyList<Feed>(), cache.loadFeeds())
    }

    @Test
    fun `totalSize は保存済みファイルの合計サイズを返す`() {
        val cache = newCache()
        assertEquals(0L, cache.totalSize)

        cache.saveFeeds(listOf(sampleFeed))
        assertTrue(cache.totalSize > 0)
    }

    @Test
    fun `clearAll はキャッシュディレクトリを空にする`() {
        val cache = newCache()
        cache.saveFeeds(listOf(sampleFeed))
        assertTrue(cache.totalSize > 0)

        cache.clearAll()

        assertEquals(0L, cache.totalSize)
        assertEquals(emptyList<Feed>(), cache.loadFeeds())
    }
}
