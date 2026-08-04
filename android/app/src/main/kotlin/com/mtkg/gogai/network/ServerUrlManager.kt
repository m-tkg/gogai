package com.mtkg.gogai.network

import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.KeyValueStore
import java.io.IOException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/// サーバー URL の保存・解決を担う（iOS ServerURLManager の移植）。
/// Gist URL の場合は GitHub Gist API 経由で実 URL（トンネル URL）を解決する。
class ServerUrlManager(
    private val keyValueStore: KeyValueStore,
    private val httpClient: OkHttpClient,
    private val gistApiBaseUrl: String = "https://api.github.com",
    private val failureDebounceMillis: Long = 30_000,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val json = Json { ignoreUnknownKeys = true }

    /// KeyValueStore に保存された生の URL（Gist URL の場合もある）
    private val _serverUrl = MutableStateFlow<String?>(null)
    val serverUrl: StateFlow<String?> = _serverUrl.asStateFlow()

    /// 実際に API クライアントが使う解決済み URL
    private val _resolvedUrl = MutableStateFlow<HttpUrl?>(null)
    val resolvedUrl: StateFlow<HttpUrl?> = _resolvedUrl.asStateFlow()

    private val _isResolving = MutableStateFlow(false)
    val isResolving: StateFlow<Boolean> = _isResolving.asStateFlow()

    val isConfigured: Boolean get() = _serverUrl.value != null

    private var lastReportedFailureAtMillis: Long? = null

    init {
        val stored = keyValueStore.getString(DefaultsKeys.SERVER_URL)
        if (stored != null) {
            _serverUrl.value = stored
            // Why: 起動時に Gist API 解決を待たず前回のトンネル URL で即座に
            // API クライアントを構成できるようキャッシュを復元する。非 Gist URL は
            // resolve() が即座に自身をセットするためキャッシュ復元は不要。
            if (isGistUrl(stored)) {
                _resolvedUrl.value = loadCachedResolvedUrl()
            }
        }
    }

    fun setServerUrl(url: String) {
        keyValueStore.putString(DefaultsKeys.SERVER_URL, url)
        keyValueStore.remove(DefaultsKeys.RESOLVED_SERVER_URL)
        _serverUrl.value = url
        _resolvedUrl.value = null
    }

    fun clearServerUrl() {
        keyValueStore.remove(DefaultsKeys.SERVER_URL)
        keyValueStore.remove(DefaultsKeys.RESOLVED_SERVER_URL)
        _serverUrl.value = null
        _resolvedUrl.value = null
    }

    /// APIClient の接続失敗通知を受けて再解決する（キャッシュ URL が失効しているかもしれない想定）。
    /// デバウンスで連続呼び出しを抑制する。
    /// - 成功時: resolvedUrl が新 URL に更新される。
    /// - 失敗時: resolvedUrl はそのまま。次回起動で再試行できる。
    suspend fun reportFailure() {
        val last = lastReportedFailureAtMillis
        val now = nowMillis()
        if (last != null && now - last < failureDebounceMillis) return
        lastReportedFailureAtMillis = now
        resolve()
    }

    /// Gist URL なら API 経由でコンテンツを取得して実 URL を解決する
    suspend fun resolve() {
        val url = _serverUrl.value ?: return
        _isResolving.value = true
        try {
            val resolved = resolveUrl(url)
            _resolvedUrl.value = resolved
            if (isGistUrl(url)) {
                cacheResolvedUrl(resolved)
            }
        } catch (e: Exception) {
            // Why: 失敗時は既存の resolvedUrl を維持する。init 時に復元した
            // キャッシュ済み URL があればそれで API を叩き続けられるし、
            // resolvedUrl が元々 null なら null のまま（setServerUrl 直後の失敗に相当）。
        } finally {
            _isResolving.value = false
        }
    }

    private fun isGistUrl(urlString: String): Boolean = urlString.toHttpUrlOrNull()?.host == "gist.github.com"

    @Serializable
    private data class GistFile(val content: String)

    @Serializable
    private data class GistResponse(val files: Map<String, GistFile>)

    /// gist.github.com URL を GitHub Gist API 経由で解決する。それ以外はそのまま HttpUrl に変換して返す。
    /// internal 可視性: ServerSetupScreen が「接続する」ボタンでの疎通確認（health チェック）のために
    /// setServerUrl() で保存する前に同じ解決ロジックを使う（iOS の `static func resolveURL` 相当）。
    internal suspend fun resolveUrl(urlString: String): HttpUrl {
        if (!isGistUrl(urlString)) {
            return urlString.toHttpUrlOrNull() ?: throw IOException("無効なURL: $urlString")
        }
        val gistUrl = urlString.toHttpUrlOrNull() ?: throw IOException("無効な Gist URL: $urlString")
        val gistId = gistUrl.pathSegments.lastOrNull { it.isNotEmpty() }
            ?: throw IOException("無効な Gist URL: $urlString")
        val apiBase = gistApiBaseUrl.toHttpUrlOrNull()
            ?: throw IOException("無効な gistApiBaseUrl: $gistApiBaseUrl")
        val apiUrl = apiBase.newBuilder().addPathSegment("gists").addPathSegment(gistId).build()
        val request = Request.Builder().url(apiUrl).build()
        val (_, bodyString) = httpClient.fetchStringResponse(request)
        val gist = json.decodeFromString(GistResponse.serializer(), bodyString)
        // Why: content が "trycloudflare.com" のような scheme/host を欠いた文字列だと
        // そのまま受け入れてしまうと APIClient が実際にリクエストを送る段階で初めて
        // 失敗し、原因が分かりにくくなる。HttpUrl.parse は http/https スキームと
        // host の両方を要求するため、ここで検証を兼ねる。
        val content = gist.files.values.firstOrNull()?.content?.trim()
            ?: throw IOException("Gist にファイルが見つかりません")
        return content.toHttpUrlOrNull() ?: throw IOException("解決した URL が不正です: $content")
    }

    // MARK: - Resolved URL cache

    private fun loadCachedResolvedUrl(): HttpUrl? {
        // Why: この検証が入る前に保存された壊れたキャッシュ値（scheme/host を欠く）が
        // 残っていることがあるため、読み込み時にも同じ検証を通す。検証せずに
        // resolvedUrl へ採用すると、起動のたびに壊れた値を使い続けてしまう。
        val cached = keyValueStore.getString(DefaultsKeys.RESOLVED_SERVER_URL) ?: return null
        return cached.toHttpUrlOrNull()
    }

    private fun cacheResolvedUrl(url: HttpUrl) {
        keyValueStore.putString(DefaultsKeys.RESOLVED_SERVER_URL, url.toString())
    }
}
