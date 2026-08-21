package com.mtkg.gogai.ai

import com.mtkg.gogai.util.sha256HexDigest
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PageTranslatorTest {
    private fun translatingGenerator(): TextGenerating = TextGenerating { _, prompt ->
        // ⟦id⟧原文 の各行に "訳:" を付けて折り返す簡易フェイク
        prompt.lines().joinToString("\n") { line ->
            val match = Regex("⟦(\\d+)⟧(.*)").find(line) ?: return@joinToString ""
            val (id, text) = match.destructured
            "⟦$id⟧訳:$text"
        }.let { it }
    }

    @Test
    fun `保存済みペイロードが空なら全ノードを翻訳する`() = runTest {
        val translator = PageTranslator(PageBatchTranslator(translatingGenerator()))
        val texts = listOf("Hello", "World")

        val result = translator.translate(texts, savedPayloadJson = null, pageTitle = "t")

        assertTrue(result.restored.isEmpty())
        assertEquals(mapOf(0 to "訳:Hello", 1 to "訳:World"), result.translatedNow)
        assertEquals(result.translatedNow, result.merged)
    }

    @Test
    fun `原文ハッシュが一致するノードは復元し翻訳リクエストしない`() = runTest {
        var called = false
        val generator = TextGenerating { _, _ -> called = true; "" }
        val translator = PageTranslator(PageBatchTranslator(generator))
        val texts = listOf("Hello", "World")

        val payload = TranslationPayload(
            version = TranslationPayload.CURRENT_VERSION,
            segments = listOf(
                TranslationPayload.Segment(i = 0, h = "Hello".sha256HexDigest(), t = "こんにちは"),
                TranslationPayload.Segment(i = 1, h = "World".sha256HexDigest(), t = "世界"),
            ),
        )
        val savedJson = Json.encodeToString(TranslationPayload.serializer(), payload)

        val result = translator.translate(texts, savedPayloadJson = savedJson, pageTitle = "t")

        assertEquals(mapOf(0 to "こんにちは", 1 to "世界"), result.restored)
        assertTrue(result.translatedNow.isEmpty())
        assertTrue(!called)
    }

    @Test
    fun `ページが変化して原文ハッシュが一致しないノードは再翻訳される`() = runTest {
        val generator = translatingGenerator()
        val translator = PageTranslator(PageBatchTranslator(generator))
        val texts = listOf("Hello", "ChangedText")

        val payload = TranslationPayload(
            version = TranslationPayload.CURRENT_VERSION,
            segments = listOf(
                TranslationPayload.Segment(i = 0, h = "Hello".sha256HexDigest(), t = "こんにちは"),
                // index 1 は保存時と原文が変わっているのでハッシュ不一致になる
                TranslationPayload.Segment(i = 1, h = "OldText".sha256HexDigest(), t = "古い訳"),
            ),
        )
        val savedJson = Json.encodeToString(TranslationPayload.serializer(), payload)

        val result = translator.translate(texts, savedPayloadJson = savedJson, pageTitle = "t")

        assertEquals(mapOf(0 to "こんにちは"), result.restored)
        assertEquals(mapOf(1 to "訳:ChangedText"), result.translatedNow)
        assertEquals(mapOf(0 to "こんにちは", 1 to "訳:ChangedText"), result.merged)
    }

    @Test
    fun `翻訳結果は保存用ペイロードJSONへエンコードされ原文ハッシュ付きでラウンドトリップできる`() = runTest {
        val translator = PageTranslator(PageBatchTranslator(translatingGenerator()))
        val texts = listOf("Hello")

        val result = translator.translate(texts, savedPayloadJson = null, pageTitle = "t")

        requireNotNull(result.payloadJson)
        val decoded = Json.decodeFromString(TranslationPayload.serializer(), result.payloadJson)
        assertEquals(TranslationPayload.CURRENT_VERSION, decoded.version)
        assertEquals(1, decoded.segments.size)
        assertEquals(0, decoded.segments[0].i)
        assertEquals("Hello".sha256HexDigest(), decoded.segments[0].h)
        assertEquals("訳:Hello", decoded.segments[0].t)
    }

    @Test
    fun `テキストが空なら翻訳せずペイロードも null を返す`() = runTest {
        val translator = PageTranslator(PageBatchTranslator(translatingGenerator()))
        val result = translator.translate(emptyList(), savedPayloadJson = null, pageTitle = "t")

        assertTrue(result.merged.isEmpty())
        assertNull(result.payloadJson)
    }

    @Test
    fun `旧形式(ノード単位 version 1)のペイロードは復元せず全文を翻訳し直す`() = runTest {
        val translator = PageTranslator(PageBatchTranslator(translatingGenerator()))
        val payload = TranslationPayload(
            version = 1,
            segments = listOf(TranslationPayload.Segment(i = 0, h = "Hello".sha256HexDigest(), t = "こんにちは")),
        )
        val savedJson = Json.encodeToString(TranslationPayload.serializer(), payload)

        val result = translator.translate(listOf("Hello"), savedPayloadJson = savedJson, pageTitle = "t")

        assertTrue(result.restored.isEmpty())
        assertEquals(mapOf(0 to "訳:Hello"), result.translatedNow)
    }

    @Test
    fun `壊れたJSONは保存済みなしとして扱われ全ノードが翻訳対象になる`() = runTest {
        val translator = PageTranslator(PageBatchTranslator(translatingGenerator()))
        val result = translator.translate(listOf("Hello"), savedPayloadJson = "not json", pageTitle = "t")

        assertEquals(mapOf(0 to "訳:Hello"), result.translatedNow)
        assertTrue(result.restored.isEmpty())
    }
}
