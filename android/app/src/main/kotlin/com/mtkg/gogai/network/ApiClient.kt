package com.mtkg.gogai.network

import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/// バックエンド API クライアント（iOS APIClient の移植）。
///
/// エラーの型分離（Store の楽観更新ロジックが依存する契約）:
/// - 接続系エラー（iOS の URLError 相当）→ IOException をそのまま投げ直す + onNetworkFailure 通知
/// - 非 2xx → ApiException.Http（onNetworkFailure は呼ばない）
/// - デコード失敗 → ApiException.Decoding
class ApiClient(
    private val baseUrl: HttpUrl,
    private val httpClient: OkHttpClient = defaultClient,
    private val onNetworkFailure: (() -> Unit)? = null,
) {
    companion object {
        val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = false
            explicitNulls = false
        }
        val defaultClient: OkHttpClient by lazy { OkHttpClient() }
        private val jsonMediaType = "application/json".toMediaType()
    }

    suspend fun <T> send(endpoint: Endpoint, deserializer: DeserializationStrategy<T>): T {
        val body = fetch(endpoint)
        return try {
            json.decodeFromString(deserializer, body)
        } catch (e: Exception) {
            throw ApiException.Decoding(e.message ?: e.toString())
        }
    }

    suspend fun sendVoid(endpoint: Endpoint) {
        fetch(endpoint)
    }

    private suspend fun fetch(endpoint: Endpoint): String {
        val request = buildRequest(endpoint)
        val (code, bodyString) = try {
            httpClient.fetchStringResponse(request)
        } catch (e: IOException) {
            // Why: 接続系エラー（トンネル URL 失効など）は ServerUrlManager に
            // キャッシュ破棄 + 再解決を促すためコールバックで通知する。
            // IOException は呼び出し側でリトライ判定するため、そのまま投げ直す。
            onNetworkFailure?.invoke()
            throw e
        }
        if (code !in 200..299) {
            throw ApiException.Http(statusCode = code, body = bodyString)
        }
        return bodyString
    }

    private fun buildRequest(endpoint: Endpoint): Request {
        val urlBuilder = baseUrl.newBuilder()
            .addPathSegments(endpoint.path.trimStart('/'))
        for ((name, value) in endpoint.queryItems) {
            urlBuilder.addQueryParameter(name, value)
        }
        val builder = Request.Builder()
            .url(urlBuilder.build())
            .header("Accept", "application/json")
        for ((field, value) in endpoint.headers) {
            builder.header(field, value)
        }
        val requestBody = endpoint.body?.toRequestBody(jsonMediaType)
        when (endpoint.method) {
            Endpoint.HttpMethod.GET -> builder.get()
            Endpoint.HttpMethod.POST -> builder.post(requestBody ?: ByteArray(0).toRequestBody(jsonMediaType))
            Endpoint.HttpMethod.PUT -> builder.put(requestBody ?: ByteArray(0).toRequestBody(jsonMediaType))
            Endpoint.HttpMethod.PATCH -> builder.patch(requestBody ?: ByteArray(0).toRequestBody(jsonMediaType))
            Endpoint.HttpMethod.DELETE -> builder.delete()
        }
        return builder.build()
    }
}

/// OkHttp Call を suspend 化する（キャンセル時は HTTP 呼び出しも中断）。
/// 注意: enqueue コールバックの継続は呼び出し元のディスパッチャ（多くは Main）で
/// 再開されるため、await() が返す Response の body を読む処理を呼び出し元の
/// コンテキストでそのまま行うとメインスレッドでソケット読み込みが走り
/// NetworkOnMainThreadException になる。body を読む場合は必ず
/// fetchStringResponse / isSuccessfulResponse 等、Dispatchers.IO 上で
/// 実行 + 読み取りまで完結するヘルパーを使うこと。
suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    enqueue(object : Callback {
        override fun onResponse(call: Call, response: Response) {
            continuation.resume(response)
        }

        override fun onFailure(call: Call, e: IOException) {
            if (!continuation.isCancelled) continuation.resumeWithException(e)
        }
    })
    continuation.invokeOnCancellation { cancel() }
}

/// リクエスト実行 + body 読み取りを Dispatchers.IO 上で行う（メインスレッドでの
/// ソケット読み込みを防ぐ）。use で確実に close するため、既知の connection leak も同時に防ぐ。
suspend fun OkHttpClient.fetchStringResponse(request: Request): Pair<Int, String> =
    withContext(Dispatchers.IO) {
        newCall(request).await().use { it.code to (it.body?.string() ?: "") }
    }

/// レスポンスの成否だけを判定する（body は読まないヘルスチェック等向け）。
/// 実行自体も Dispatchers.IO 上で行い、close 漏れを use で防ぐ。
suspend fun OkHttpClient.isSuccessfulResponse(request: Request): Boolean =
    withContext(Dispatchers.IO) {
        newCall(request).await().use { it.isSuccessful }
    }
