package com.mtkg.gogai.ai

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeTextGenerator(private val handler: suspend (String, String) -> String) : TextGenerating {
    var callCount = 0
        private set
    var lastInstructions: String? = null
        private set
    var lastPrompt: String? = null
        private set

    override suspend fun generate(instructions: String, prompt: String): String {
        callCount++
        lastInstructions = instructions
        lastPrompt = prompt
        return handler(instructions, prompt)
    }
}

class StockSummarizerTest {
    @Test
    fun `本文が100文字以下ならAI要約をスキップする`() = runTest {
        val generator = FakeTextGenerator { _, _ -> error("呼ばれてはいけない") }
        val summarizer = StockSummarizer(generator)

        val shortText = "短い本文です。"
        assertTrue(shortText.length <= StockSummarizer.NO_SUMMARY_NEEDED_TEXT_LIMIT)

        val result = summarizer.summarize(title = "タイトル", text = shortText)

        assertEquals(0, generator.callCount)
        assertTrue(result.contains(StockSummarizer.SECTION_PLACEHOLDER))
        assertTrue(result.contains("内容が少ないため、要約せず本文をそのまま表示します。"))
        assertTrue(result.contains(shortText))
    }

    @Test
    fun `本文が20000文字を超えると外部AI向けに切り詰められる`() = runTest {
        val longText = "a".repeat(StockSummarizer.REMOTE_MAX_PROMPT_LENGTH + 500)
        val generator = FakeTextGenerator { _, prompt -> "## 何についての記事か\nt\n## 何の目的で書かれたか\np\n## 筆者が一番伝えたいこと\nm\n## 要約\n$prompt".take(50) }
        val summarizer = StockSummarizer(generator)

        summarizer.summarize(title = null, text = longText)

        assertEquals(1, generator.callCount)
        // title が空なので prompt はそのまま切り詰め後の本文
        assertEquals(StockSummarizer.REMOTE_MAX_PROMPT_LENGTH, generator.lastPrompt!!.length)
    }

    @Test
    fun `パース失敗時は固定見出しでラップする`() = runTest {
        val body = "a".repeat(StockSummarizer.NO_SUMMARY_NEEDED_TEXT_LIMIT + 50)
        val generator = FakeTextGenerator { _, _ -> "見出しのない生の応答行1\n見出しのない生の応答行2" }
        val summarizer = StockSummarizer(generator)

        val result = summarizer.summarize(title = "タイトル", text = body)

        assertTrue(result.contains("## 何についての記事か"))
        assertTrue(result.contains(StockSummarizer.SECTION_PLACEHOLDER))
        assertTrue(result.contains("見出しのない生の応答行1"))
        assertTrue(result.contains("見出しのない生の応答行2"))
        // 固定見出しで組み立て直された結果は改めて parse に成功し、学びはプレースホルダで埋まる
        assertEquals(listOf(StockSummarizer.SECTION_PLACEHOLDER), StockSummary.parse(result)?.learningLines)
    }

    @Test
    fun `enforceSummaryLineLimit は要約セクションを limit 行までに切り詰め後続セクションは保持する`() {
        val summaryLines = (1..25).map { "行$it" }
        val text = "## 要約\n" + summaryLines.joinToString("\n") + "\n## この記事から得られる学び\n学び1"

        val limited = StockSummarizer.enforceSummaryLineLimit(text, limit = 20)
        val lines = limited.split("\n")

        assertEquals("## 要約", lines.first())
        val nextHeadingIndex = lines.indexOf("## この記事から得られる学び")
        assertTrue(nextHeadingIndex > 0)
        val summaryBodyLines = lines.subList(1, nextHeadingIndex)
        assertEquals(20, summaryBodyLines.size)
        assertEquals("行1", summaryBodyLines.first())
        assertEquals("行20", summaryBodyLines.last())
        assertEquals(listOf("## この記事から得られる学び", "学び1"), lines.subList(nextHeadingIndex, lines.size))
    }

    @Test
    fun `行数が limit 以下ならenforceSummaryLineLimitは変更しない`() {
        val text = "## 要約\n行1\n行2"
        assertEquals(text, StockSummarizer.enforceSummaryLineLimit(text, limit = 20))
    }

    @Test
    fun `タイトル・本文がともに空なら EmptyContent を投げる`() = runTest {
        val generator = FakeTextGenerator { _, _ -> error("呼ばれてはいけない") }
        val summarizer = StockSummarizer(generator)
        try {
            summarizer.summarize(title = "", text = "")
            assertFalse("例外が投げられるべき", true)
        } catch (e: AiError.EmptyContent) {
            // expected
        }
    }
}
