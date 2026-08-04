package com.mtkg.gogai.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TranslationCacheTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun `store した訳文を同じ namespace で取得できる`() {
        val cache = TranslationCache(tempFolder.newFolder())
        cache.store(source = "Hello", target = "こんにちは", namespace = "foundationModel")

        assertEquals("こんにちは", cache.target(source = "Hello", namespace = "foundationModel"))
    }

    @Test
    fun `namespace が違えば別エントリとして扱われる`() {
        val cache = TranslationCache(tempFolder.newFolder())
        cache.store(source = "Hello", target = "こんにちは", namespace = "foundationModel")

        assertNull(cache.target(source = "Hello", namespace = "translationFramework"))
    }

    @Test
    fun `未登録の原文は null を返す`() {
        val cache = TranslationCache(tempFolder.newFolder())
        assertNull(cache.target(source = "unknown", namespace = "foundationModel"))
    }

    @Test
    fun `persist してディスクへ保存した内容を新しいインスタンスから読み込める`() {
        val dir = tempFolder.newFolder()
        val cache = TranslationCache(dir)
        cache.store(source = "Hello", target = "こんにちは", namespace = "foundationModel")
        cache.persist()

        val reloaded = TranslationCache(dir)
        assertEquals("こんにちは", reloaded.target(source = "Hello", namespace = "foundationModel"))
    }

    @Test
    fun `TTL(7日)を過ぎたエントリは失効として扱われる`() {
        val cache = TranslationCache(tempFolder.newFolder())
        val now = 1_000_000_000_000L
        cache.store(source = "Hello", target = "こんにちは", namespace = "foundationModel", nowEpochMillis = now)

        val justBeforeExpiry = now + TranslationCache.TIME_TO_LIVE_MILLIS - 1
        assertEquals("こんにちは", cache.target(source = "Hello", namespace = "foundationModel", nowEpochMillis = justBeforeExpiry))

        val afterExpiry = now + TranslationCache.TIME_TO_LIVE_MILLIS
        assertNull(cache.target(source = "Hello", namespace = "foundationModel", nowEpochMillis = afterExpiry))
    }

    @Test
    fun `persist は失効エントリをディスクから削除する`() {
        val dir = tempFolder.newFolder()
        val cache = TranslationCache(dir)
        val now = 1_000_000_000_000L
        cache.store(source = "Hello", target = "こんにちは", namespace = "foundationModel", nowEpochMillis = now)

        val afterExpiry = now + TranslationCache.TIME_TO_LIVE_MILLIS
        cache.persist(nowEpochMillis = afterExpiry)

        val reloaded = TranslationCache(dir)
        assertNull(reloaded.target(source = "Hello", namespace = "foundationModel", nowEpochMillis = afterExpiry))
    }

    @Test
    fun `壊れたJSONファイルがあっても空として起動できる`() {
        val dir = tempFolder.newFolder()
        java.io.File(dir, "translationCache.json").writeText("not json at all")

        val cache = TranslationCache(dir)
        assertNull(cache.target(source = "Hello", namespace = "foundationModel"))
    }
}
