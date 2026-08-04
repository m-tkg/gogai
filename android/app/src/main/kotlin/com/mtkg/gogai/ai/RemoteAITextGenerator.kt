package com.mtkg.gogai.ai

import com.mtkg.gogai.network.fetchStringResponse
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

// MARK: - リクエスト/レスポンス JSON 形状（iOS RemoteAITextGenerator.swift から転記）

@Serializable
private data class OpenAiRequest(val model: String, val instructions: String, val input: String)

@Serializable
private data class OpenAiOutputContent(val type: String? = null, val text: String? = null)

@Serializable
private data class OpenAiOutput(val content: List<OpenAiOutputContent>? = null)

@Serializable
private data class OpenAiResponse(val output_text: String? = null, val output: List<OpenAiOutput>? = null)

@Serializable
private data class GeminiRequest(val model: String, val system_instruction: String, val input: String)

@Serializable
private data class GeminiStepContent(val type: String? = null, val text: String? = null)

@Serializable
private data class GeminiStep(val content: List<GeminiStepContent>? = null)

@Serializable
private data class GeminiPart(val text: String? = null)

@Serializable
private data class GeminiCandidateContent(val parts: List<GeminiPart>? = null)

@Serializable
private data class GeminiCandidate(val content: GeminiCandidateContent? = null)

@Serializable
private data class GeminiResponse(
    val output_text: String? = null,
    val steps: List<GeminiStep>? = null,
    val candidates: List<GeminiCandidate>? = null,
)

@Serializable
private data class ClaudeMessage(val role: String, val content: String)

@Serializable
private data class ClaudeRequest(
    val model: String,
    val max_tokens: Int,
    val system: String,
    val messages: List<ClaudeMessage>,
)

@Serializable
private data class ClaudeContent(val type: String, val text: String? = null)

@Serializable
private data class ClaudeResponse(val content: List<ClaudeContent>)

/** 接続系エラー（iOS の URLError 相当）のラップ。タイムアウトのみ専用メッセージにする。 */
class RemoteAiTransportError(val underlying: IOException) : Exception(
    if (underlying is SocketTimeoutException) {
        "AI API のリクエストがタイムアウトしました。時間を置いて再試行してください。"
    } else {
        underlying.message ?: underlying.toString()
    },
    underlying,
)

/** 非 2xx 応答のエラー（iOS の RemoteAIHTTPError 相当） */
class RemoteAiHttpError(val statusCode: Int, val responseBody: String) : Exception(
    responseBody.trim().let { body ->
        if (body.isEmpty()) {
            "AI API が HTTP $statusCode を返しました。"
        } else {
            "AI API が HTTP $statusCode を返しました: ${body.take(500)}"
        }
    },
)

/**
 * OpenAI / Gemini / Claude のテキスト生成 API を [TextGenerating] に揃える実装
 * （iOS RemoteAITextGenerator, AI/FoundationModelTextGenerator.swift の移植）。
 * エンドポイント・モデル名・JSON 形状は iOS 原文から転記している。
 *
 * [baseUrls] はテスト時に MockWebServer の URL へ差し替えるためのコンストラクタ引数。
 * 省略時は各プロバイダの本番エンドポイントを使う。
 */
class RemoteAITextGenerator(
    private val provider: AiProvider,
    private val apiKey: String,
    private val httpClient: OkHttpClient = defaultClient,
    private val baseUrls: BaseUrls = BaseUrls(),
) : TextGenerating {

    data class BaseUrls(
        val openAI: String = "https://api.openai.com/v1/responses",
        val gemini: String = "https://generativelanguage.googleapis.com/v1beta/interactions",
        val claude: String = "https://api.anthropic.com/v1/messages",
    )

    override suspend fun generate(instructions: String, prompt: String): String {
        try {
            return when (provider) {
                AiProvider.OpenAI -> generateOpenAI(instructions, prompt)
                AiProvider.Gemini -> generateGemini(instructions, prompt)
                AiProvider.Claude -> generateClaude(instructions, prompt)
                AiProvider.Automatic -> throw AiError.AiUnavailable
            }
        } catch (e: IOException) {
            throw RemoteAiTransportError(e)
        }
    }

    private suspend fun generateOpenAI(instructions: String, prompt: String): String {
        val body = OpenAiRequest(model = "gpt-5.5", instructions = instructions, input = prompt)
        val data = postJson(
            url = baseUrls.openAI,
            headers = mapOf("Authorization" to "Bearer $apiKey"),
            bodyJson = json.encodeToString(OpenAiRequest.serializer(), body),
        )
        val response = json.decodeFromString(OpenAiResponse.serializer(), data)
        response.output_text?.takeIf { it.isNotEmpty() }?.let { return it }
        val text = response.output.orEmpty()
            .flatMap { it.content.orEmpty() }
            .mapNotNull { it.text }
            .joinToString("\n")
        if (text.isEmpty()) throw AiError.ParseFailed
        return text
    }

    private suspend fun generateGemini(instructions: String, prompt: String): String {
        val body = GeminiRequest(model = "gemini-3.5-flash", system_instruction = instructions, input = prompt)
        val data = postJson(
            url = baseUrls.gemini,
            headers = mapOf("x-goog-api-key" to apiKey),
            bodyJson = json.encodeToString(GeminiRequest.serializer(), body),
        )
        val response = json.decodeFromString(GeminiResponse.serializer(), data)
        response.output_text?.takeIf { it.isNotEmpty() }?.let { return it }
        val stepText = response.steps.orEmpty()
            .flatMap { it.content.orEmpty() }
            .mapNotNull { it.text }
            .joinToString("\n")
        if (stepText.isNotEmpty()) return stepText
        val text = response.candidates.orEmpty()
            .mapNotNull { it.content }
            .flatMap { it.parts.orEmpty() }
            .mapNotNull { it.text }
            .joinToString("\n")
        if (text.isEmpty()) throw AiError.ParseFailed
        return text
    }

    private suspend fun generateClaude(instructions: String, prompt: String): String {
        val body = ClaudeRequest(
            model = "claude-sonnet-4-5",
            max_tokens = 4096,
            system = instructions,
            messages = listOf(ClaudeMessage(role = "user", content = prompt)),
        )
        val data = postJson(
            url = baseUrls.claude,
            headers = mapOf("x-api-key" to apiKey, "anthropic-version" to "2023-06-01"),
            bodyJson = json.encodeToString(ClaudeRequest.serializer(), body),
        )
        val response = json.decodeFromString(ClaudeResponse.serializer(), data)
        val text = response.content.mapNotNull { it.text }.joinToString("\n")
        if (text.isEmpty()) throw AiError.ParseFailed
        return text
    }

    private suspend fun postJson(url: String, headers: Map<String, String>, bodyJson: String): String {
        val requestBuilder = Request.Builder()
            .url(url)
            .header("Content-Type", "application/json")
        for ((key, value) in headers) requestBuilder.header(key, value)
        val request = requestBuilder.post(bodyJson.toRequestBody(jsonMediaType)).build()
        val (code, bodyString) = httpClient.fetchStringResponse(request)
        if (code !in 200..299) {
            throw RemoteAiHttpError(statusCode = code, responseBody = bodyString)
        }
        return bodyString
    }

    companion object {
        private val jsonMediaType = "application/json".toMediaType()
        val json: Json = Json { ignoreUnknownKeys = true }

        /**
         * タイムアウト: リクエスト 180 秒 / リソース(コネクション全体) 300 秒
         * （iOS URLSession.remoteAI, AI/FoundationModelTextGenerator.swift 相当）。
         */
        val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(180, TimeUnit.SECONDS)
                .readTimeout(180, TimeUnit.SECONDS)
                .writeTimeout(180, TimeUnit.SECONDS)
                .callTimeout(300, TimeUnit.SECONDS)
                .build()
        }
    }
}
