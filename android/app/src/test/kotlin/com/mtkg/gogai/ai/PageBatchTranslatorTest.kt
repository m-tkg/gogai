package com.mtkg.gogai.ai

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PageBatchTranslatorTest {
    // MARK: - makeBatches (1800 文字予算)

    @Test
    fun `合計文字数が予算内なら1バッチにまとまる`() {
        val segments = listOf(
            PageBatchTranslator.Segment(0, "a".repeat(500)),
            PageBatchTranslator.Segment(1, "b".repeat(500)),
        )
        val batches = PageBatchTranslator.makeBatches(segments, charBudget = 1800)
        assertEquals(1, batches.size)
        assertEquals(2, batches[0].size)
    }

    @Test
    fun `予算を超える境界で新しいバッチに分割される`() {
        val segments = listOf(
            PageBatchTranslator.Segment(0, "a".repeat(1000)),
            PageBatchTranslator.Segment(1, "b".repeat(1000)), // 合計 2000 > 1800 のためここで分割
            PageBatchTranslator.Segment(2, "c".repeat(100)),
        )
        val batches = PageBatchTranslator.makeBatches(segments, charBudget = 1800)
        assertEquals(2, batches.size)
        assertEquals(listOf(0), batches[0].map { it.index })
        assertEquals(listOf(1, 2), batches[1].map { it.index })
    }

    @Test
    fun `単一セグメントが予算を超えていても単独バッチとして許容する`() {
        val segments = listOf(PageBatchTranslator.Segment(0, "a".repeat(5000)))
        val batches = PageBatchTranslator.makeBatches(segments, charBudget = 1800)
        assertEquals(1, batches.size)
        assertEquals(1, batches[0].size)
    }

    // MARK: - buildPrompt / instructions

    @Test
    fun `buildPrompt は ctx 行と id 付き本文行を組み立てる`() {
        val prompt = PageBatchTranslator.buildPrompt(
            batch = listOf(PageBatchTranslator.Segment(1, "Hello"), PageBatchTranslator.Segment(2, "World")),
            contextText = "context here",
        )
        assertEquals("⟦ctx⟧context here\n⟦1⟧Hello\n⟦2⟧World", prompt)
    }

    @Test
    fun `contextText が空なら ctx 行を含めない`() {
        val prompt = PageBatchTranslator.buildPrompt(
            batch = listOf(PageBatchTranslator.Segment(0, "Hi")),
            contextText = null,
        )
        assertEquals("⟦0⟧Hi", prompt)
    }

    // MARK: - parseResponse (⟦id⟧ パース)

    @Test
    fun `id タグ付き応答を id から訳文へのマップにパースする`() {
        val response = "⟦0⟧こんにちは\n⟦1⟧世界"
        val parsed = PageBatchTranslator.parseResponse(response)
        assertEquals(mapOf(0 to "こんにちは", 1 to "世界"), parsed)
    }

    @Test
    fun `ctx など数字でない id は無視される`() {
        val response = "⟦ctx⟧参考情報\n⟦0⟧翻訳結果"
        val parsed = PageBatchTranslator.parseResponse(response)
        assertEquals(mapOf(0 to "翻訳結果"), parsed)
    }

    @Test
    fun `各セグメントの内容は前後の空白を取り除く`() {
        val response = "⟦0⟧  余白あり  \n⟦1⟧次"
        val parsed = PageBatchTranslator.parseResponse(response)
        assertEquals("余白あり", parsed[0])
    }

    // MARK: - translate (欠落 id の個別リトライ)

    @Test
    fun `バッチ応答から欠落した id は単体で個別リトライされる`() = runTest {
        var callCount = 0
        val generator = TextGenerating { _, prompt ->
            callCount++
            if (prompt.contains("⟦1⟧") && prompt.contains("⟦0⟧")) {
                // バッチリクエスト: id=1 の訳文だけ欠落させる
                "⟦0⟧翻訳0"
            } else {
                // id=1 の単体リトライ
                "⟦1⟧翻訳1"
            }
        }
        val translator = PageBatchTranslator(generator)
        val texts = listOf("原文0", "原文1")

        val result = translator.translate(texts, indicesToTranslate = listOf(0, 1), pageTitle = "タイトル")

        assertEquals(mapOf(0 to "翻訳0", 1 to "翻訳1"), result)
        assertEquals(2, callCount) // バッチ1回 + 個別リトライ1回
    }

    @Test
    fun `個別リトライにも失敗したノードは戻り値に含まれない`() = runTest {
        val generator = TextGenerating { _, _ -> "応答に id タグなし" }
        val translator = PageBatchTranslator(generator)
        val texts = listOf("原文0")

        val result = translator.translate(texts, indicesToTranslate = listOf(0), pageTitle = "タイトル")

        assertTrue(result.isEmpty())
    }

    @Test
    fun `indicesToTranslate が空なら generator を呼ばず空マップを返す`() = runTest {
        var called = false
        val generator = TextGenerating { _, _ -> called = true; "" }
        val translator = PageBatchTranslator(generator)

        val result = translator.translate(listOf("a", "b"), indicesToTranslate = emptyList(), pageTitle = "t")

        assertTrue(result.isEmpty())
        assertTrue(!called)
    }

    @Test
    fun `parseResponse は id が見つからなければ空マップを返す`() {
        assertEquals(emptyMap<Int, String>(), PageBatchTranslator.parseResponse("見出しもidも無いテキスト"))
    }

    @Test
    fun `translateSingle 相当の単体呼び出しで応答にidが無ければ ParseFailed 経由でスキップされる`() = runTest {
        val generator = TextGenerating { _, _ -> throw AiError.ParseFailed }
        val translator = PageBatchTranslator(generator)
        val result = translator.translate(listOf("原文"), indicesToTranslate = listOf(0), pageTitle = "t")
        assertNull(result[0])
    }
}
