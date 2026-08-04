package com.mtkg.gogai.network

/// API リクエスト定義（iOS Endpoint の移植）。body は JSON 文字列。
data class Endpoint(
    val path: String,
    val method: HttpMethod = HttpMethod.GET,
    val queryItems: List<Pair<String, String>> = emptyList(),
    val body: String? = null,
    val headers: Map<String, String> = emptyMap(),
) {
    enum class HttpMethod { GET, POST, PUT, PATCH, DELETE }

    companion object {
        fun get(path: String, queryItems: List<Pair<String, String>> = emptyList(), headers: Map<String, String> = emptyMap()) =
            Endpoint(path, HttpMethod.GET, queryItems, headers = headers)

        fun post(path: String, body: String? = null, headers: Map<String, String> = emptyMap()) =
            Endpoint(path, HttpMethod.POST, body = body, headers = headers)

        fun put(path: String, body: String) = Endpoint(path, HttpMethod.PUT, body = body)

        fun patch(path: String, body: String) = Endpoint(path, HttpMethod.PATCH, body = body)

        fun delete(path: String) = Endpoint(path, HttpMethod.DELETE)
    }
}
