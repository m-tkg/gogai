package com.mtkg.gogai.ai

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeLocalArticleGenerator(private val handler: suspend (String, String) -> String) : TextGenerating {
    var lastInstructions: String? = null
        private set
    var lastPrompt: String? = null
        private set

    override suspend fun generate(instructions: String, prompt: String): String {
        lastInstructions = instructions
        lastPrompt = prompt
        return handler(instructions, prompt)
    }
}

class LocalArticleAITest {
    @Test
    fun `summarize は日本語要約の指示とタイトル+本文のプロンプトを渡す`() = runTest {
        val generator = FakeLocalArticleGenerator { _, _ -> "要約結果" }
        val ai = LocalArticleAI(generator)

        val result = ai.summarize(title = "タイトル", content = "<p>本文</p>")

        assertEquals("要約結果", result)
        assertTrue(generator.lastInstructions!!.contains("要約"))
        assertEquals("タイトル\n\n本文", generator.lastPrompt)
    }

    @Test
    fun `translateToJapanese は翻訳の指示を渡す`() = runTest {
        val generator = FakeLocalArticleGenerator { _, _ -> "訳文" }
        val ai = LocalArticleAI(generator)

        val result = ai.translateToJapanese(title = "T", content = "C")

        assertEquals("訳文", result)
        assertTrue(generator.lastInstructions!!.contains("翻訳"))
    }

    @Test
    fun `タイトル・本文がともに空なら EmptyContent を投げる`() = runTest {
        val generator = FakeLocalArticleGenerator { _, _ -> error("呼ばれてはいけない") }
        val ai = LocalArticleAI(generator)
        try {
            ai.summarize(title = null, content = null)
            assertTrue("例外が投げられるべき", false)
        } catch (e: AiError.EmptyContent) {
            // expected
        }
    }

    @Test
    fun `preparePrompt は MAX_PROMPT_LENGTH で切り詰める`() {
        val longContent = "a".repeat(LocalArticleAI.MAX_PROMPT_LENGTH + 500)
        val prompt = LocalArticleAI.preparePrompt(title = null, content = longContent)
        assertEquals(LocalArticleAI.MAX_PROMPT_LENGTH, prompt.length)
    }

    @Test
    fun `preparePrompt は HTML タグを除去する`() {
        val prompt = LocalArticleAI.preparePrompt(title = null, content = "<p>hello <b>world</b></p>")
        assertEquals("hello world", prompt)
    }
}
