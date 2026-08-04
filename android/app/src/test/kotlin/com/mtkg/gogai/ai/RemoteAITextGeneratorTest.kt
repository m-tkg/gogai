package com.mtkg.gogai.ai

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class RemoteAITextGeneratorTest {
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

    private fun baseUrls(): RemoteAITextGenerator.BaseUrls = RemoteAITextGenerator.BaseUrls(
        openAI = server.url("/v1/responses").toString(),
        gemini = server.url("/v1beta/interactions").toString(),
        claude = server.url("/v1/messages").toString(),
    )

    // MARK: - OpenAI

    @Test
    fun `OpenAI へのリクエスト形状と output_text のパース`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"output_text":"summary text"}"""))
        val generator = RemoteAITextGenerator(AiProvider.OpenAI, apiKey = "test-key", baseUrls = baseUrls())

        val result = generator.generate("instructions text", "prompt text")
        assertEquals("summary text", result)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/v1/responses", recorded.path)
        assertEquals("Bearer test-key", recorded.getHeader("Authorization"))
        // OkHttp は MediaType に charset を付与するため前方一致で検証する
        assertEquals(true, recorded.getHeader("Content-Type")?.startsWith("application/json"))
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("gpt-5.5", body["model"]!!.jsonPrimitive.content)
        assertEquals("instructions text", body["instructions"]!!.jsonPrimitive.content)
        assertEquals("prompt text", body["input"]!!.jsonPrimitive.content)
    }

    @Test
    fun `OpenAI は output_text が空なら output content text を連結する`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"output_text":"","output":[{"content":[{"type":"output_text","text":"line1"}]},{"content":[{"type":"output_text","text":"line2"}]}]}""",
            ),
        )
        val generator = RemoteAITextGenerator(AiProvider.OpenAI, apiKey = "k", baseUrls = baseUrls())
        assertEquals("line1\nline2", generator.generate("i", "p"))
    }

    @Test
    fun `OpenAI は output_text も output もともに空なら ParseFailed`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"output_text":null,"output":null}"""))
        val generator = RemoteAITextGenerator(AiProvider.OpenAI, apiKey = "k", baseUrls = baseUrls())
        try {
            generator.generate("i", "p")
            fail("AiError.ParseFailed が投げられるべき")
        } catch (e: AiError.ParseFailed) {
            // expected
        }
    }

    // MARK: - Gemini

    @Test
    fun `Gemini へのリクエスト形状と output_text のパース`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"output_text":"gemini summary"}"""))
        val generator = RemoteAITextGenerator(AiProvider.Gemini, apiKey = "gemini-key", baseUrls = baseUrls())

        val result = generator.generate("instructions", "prompt")
        assertEquals("gemini summary", result)

        val recorded = server.takeRequest()
        assertEquals("/v1beta/interactions", recorded.path)
        assertEquals("gemini-key", recorded.getHeader("x-goog-api-key"))
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("gemini-3.5-flash", body["model"]!!.jsonPrimitive.content)
        assertEquals("instructions", body["system_instruction"]!!.jsonPrimitive.content)
        assertEquals("prompt", body["input"]!!.jsonPrimitive.content)
    }

    @Test
    fun `Gemini は output_text が空なら steps content text を連結する`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"steps":[{"content":[{"type":"text","text":"step1"}]},{"content":[{"type":"text","text":"step2"}]}]}""",
            ),
        )
        val generator = RemoteAITextGenerator(AiProvider.Gemini, apiKey = "k", baseUrls = baseUrls())
        assertEquals("step1\nstep2", generator.generate("i", "p"))
    }

    @Test
    fun `Gemini は output_text と steps が空なら candidates parts text を連結する`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"candidates":[{"content":{"parts":[{"text":"cand1"},{"text":"cand2"}]}}]}""",
            ),
        )
        val generator = RemoteAITextGenerator(AiProvider.Gemini, apiKey = "k", baseUrls = baseUrls())
        assertEquals("cand1\ncand2", generator.generate("i", "p"))
    }

    @Test
    fun `Gemini は3経路すべて空なら ParseFailed`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{}"""))
        val generator = RemoteAITextGenerator(AiProvider.Gemini, apiKey = "k", baseUrls = baseUrls())
        try {
            generator.generate("i", "p")
            fail("AiError.ParseFailed が投げられるべき")
        } catch (e: AiError.ParseFailed) {
            // expected
        }
    }

    // MARK: - Claude

    @Test
    fun `Claude へのリクエスト形状とレスポンスパース`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"content":[{"type":"text","text":"claude line1"},{"type":"text","text":"claude line2"}]}""",
            ),
        )
        val generator = RemoteAITextGenerator(AiProvider.Claude, apiKey = "claude-key", baseUrls = baseUrls())

        val result = generator.generate("system instructions", "user prompt")
        assertEquals("claude line1\nclaude line2", result)

        val recorded = server.takeRequest()
        assertEquals("/v1/messages", recorded.path)
        assertEquals("claude-key", recorded.getHeader("x-api-key"))
        assertEquals("2023-06-01", recorded.getHeader("anthropic-version"))
        val body = Json.parseToJsonElement(recorded.body.readUtf8()).jsonObject
        assertEquals("claude-sonnet-4-5", body["model"]!!.jsonPrimitive.content)
        assertEquals(4096, body["max_tokens"]!!.jsonPrimitive.content.toInt())
        assertEquals("system instructions", body["system"]!!.jsonPrimitive.content)
        val messages = body["messages"]!!.jsonArray
        assertEquals(1, messages.size)
        assertEquals("user", messages[0].jsonObject["role"]!!.jsonPrimitive.content)
        assertEquals("user prompt", messages[0].jsonObject["content"]!!.jsonPrimitive.content)
    }

    @Test
    fun `Claude はレスポンスの content が空なら ParseFailed`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"content":[]}"""))
        val generator = RemoteAITextGenerator(AiProvider.Claude, apiKey = "k", baseUrls = baseUrls())
        try {
            generator.generate("i", "p")
            fail("AiError.ParseFailed が投げられるべき")
        } catch (e: AiError.ParseFailed) {
            // expected
        }
    }

    // MARK: - 共通

    @Test
    fun `非 2xx は RemoteAiHttpError を投げる`() = runTest {
        server.enqueue(MockResponse().setResponseCode(500).setBody("internal error"))
        val generator = RemoteAITextGenerator(AiProvider.OpenAI, apiKey = "k", baseUrls = baseUrls())
        try {
            generator.generate("i", "p")
            fail("RemoteAiHttpError が投げられるべき")
        } catch (e: RemoteAiHttpError) {
            assertEquals(500, e.statusCode)
            assertTrue(e.message!!.contains("500"))
            assertTrue(e.message!!.contains("internal error"))
        }
    }

    @Test
    fun `Automatic プロバイダは AiUnavailable を投げる`() = runTest {
        val generator = RemoteAITextGenerator(AiProvider.Automatic, apiKey = "k", baseUrls = baseUrls())
        try {
            generator.generate("i", "p")
            fail("AiError.AiUnavailable が投げられるべき")
        } catch (e: AiError.AiUnavailable) {
            // expected
        }
    }
}
