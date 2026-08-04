package com.mtkg.gogai.store

import com.mtkg.gogai.model.Article
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArticleCollectionTest {
    private fun makeArticle(id: Int, feedId: Int = 1, isRead: Int = 0) = Article(
        id = id,
        feed_id = feedId,
        guid = "guid-$id",
        title = "Title $id",
        is_read = isRead,
        created_at = "2024-01-01T00:00:00Z",
    )

    // MARK: - merge

    @Test
    fun `merge isFullFetch は全置換する`() {
        val collection = ArticleCollection()
        collection.merge(listOf(makeArticle(id = 1, feedId = 1), makeArticle(id = 2, feedId = 2)), isFullFetch = true)
        collection.merge(listOf(makeArticle(id = 3, feedId = 3)), isFullFetch = true)
        assertEquals(listOf(3), collection.articles.map { it.id })
    }

    @Test
    fun `merge 部分フェッチはフェッチ結果に含まれるフィードのみ差し替える`() {
        val collection = ArticleCollection()
        collection.merge(listOf(makeArticle(id = 1, feedId = 1), makeArticle(id = 2, feedId = 2)), isFullFetch = true)
        collection.merge(listOf(makeArticle(id = 10, feedId = 1)), isFullFetch = false)
        assertEquals(setOf(2, 10), collection.articles.map { it.id }.toSet())
    }

    @Test
    fun `merge 部分フェッチの結果が空なら既存を保持する`() {
        val collection = ArticleCollection()
        collection.merge(listOf(makeArticle(id = 1, feedId = 1)), isFullFetch = true)
        collection.merge(emptyList(), isFullFetch = false)
        assertEquals(listOf(1), collection.articles.map { it.id })
    }

    // MARK: - upsert / updateAll

    @Test
    fun `upsert は一致する記事を差し替える`() {
        val collection = ArticleCollection()
        collection.merge(listOf(makeArticle(id = 1, isRead = 0)), isFullFetch = true)
        collection.upsert(makeArticle(id = 1, isRead = 1))
        assertTrue(collection.articles[0].isRead)
    }

    @Test
    fun `upsert は未知の id を無視する`() {
        val collection = ArticleCollection()
        collection.merge(listOf(makeArticle(id = 1)), isFullFetch = true)
        collection.upsert(makeArticle(id = 99))
        assertEquals(1, collection.articles.size)
    }

    @Test
    fun `updateAll は全記事に変換を適用する`() {
        val collection = ArticleCollection()
        collection.merge(listOf(makeArticle(id = 1, isRead = 0), makeArticle(id = 2, isRead = 0)), isFullFetch = true)
        collection.updateAll { it.updating(isRead = 1) }
        assertTrue(collection.articles.all { it.isRead })
    }

    // MARK: - replaceAll / isEmpty

    @Test
    fun `replaceAll は記事を置き換える`() {
        val collection = ArticleCollection()
        collection.replaceAll(listOf(makeArticle(id = 5)))
        assertEquals(listOf(5), collection.articles.map { it.id })
    }

    @Test
    fun `isEmpty`() {
        val collection = ArticleCollection()
        assertTrue(collection.isEmpty)
        collection.replaceAll(listOf(makeArticle(id = 1)))
        assertFalse(collection.isEmpty)
    }
}
