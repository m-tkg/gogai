package com.mtkg.gogai.network

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/// API エラー（iOS APIError の移植）。
/// 接続系エラー（URLError 相当）は java.io.IOException をそのまま伝播させ、
/// 呼び出し側（Store）がリトライ／pending キュー判定に使う。
sealed class ApiException(message: String) : Exception(message) {

    class InvalidUrl : ApiException("無効なURL")

    class Network(val detail: String) : ApiException("ネットワークエラー: $detail")

    class Http(val statusCode: Int, val body: String) : ApiException(describe(statusCode, body)) {
        companion object {
            private fun describe(statusCode: Int, body: String): String {
                // body から {"error":"..."} を取り出して表示
                val msg = runCatching {
                    Json.parseToJsonElement(body).jsonObject["error"]?.jsonPrimitive?.content
                }.getOrNull()
                return when {
                    msg != null -> "HTTPエラー $statusCode: $msg"
                    body.isEmpty() -> "HTTPエラー: $statusCode"
                    else -> "HTTPエラー $statusCode: $body"
                }
            }
        }
    }

    class Decoding(val detail: String) : ApiException("デコードエラー: $detail")
}
