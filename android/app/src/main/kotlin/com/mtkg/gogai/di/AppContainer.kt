package com.mtkg.gogai.di

import android.content.Context
import com.mtkg.gogai.ai.AiError
import com.mtkg.gogai.ai.AiProvider
import com.mtkg.gogai.ai.RemoteAITextGenerator
import com.mtkg.gogai.ai.StockSummarizer
import com.mtkg.gogai.ai.TextGenerating
import com.mtkg.gogai.ai.currentAiProvider
import com.mtkg.gogai.ai.resolve
import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.cache.KeyValueStore
import com.mtkg.gogai.cache.KeystoreSecretStore
import com.mtkg.gogai.cache.SecretStore
import com.mtkg.gogai.cache.SharedPreferencesStore
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.ServerUrlManager
import com.mtkg.gogai.store.ArticleStore
import com.mtkg.gogai.store.FeedStore
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.store.SettingsStore
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.store.StockSummarizing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.HttpUrl
import okhttp3.OkHttpClient

/// アプリ全体のオブジェクトグラフ（iOS GogaiApp の @StateObject 群 + configureStores() 相当）。
///
/// Store インスタンスはアプリ生存期間で 1 個ずつ保持し、resolvedUrl が変わるたびに
/// configureStores() で ApiClient を再設定する（Store 自体は再生成しない）。
/// これは各 Store が既に configure(client) メソッドを持つ実装になっているため、
/// その形に自然に合わせた設計判断（iOS の GogaiApp.configureStores と同型）。
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    /// iOS の各 Store が @MainActor で駆動されるのに合わせ、Dispatchers.Main.immediate を使う。
    /// SupervisorJob により一部の子コルーチンの失敗が他へ伝播しない。
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val prefs = appContext.getSharedPreferences("gogai", Context.MODE_PRIVATE)
    val keyValueStore: KeyValueStore = SharedPreferencesStore(prefs)
    val secretStore: SecretStore = KeystoreSecretStore(prefs)
    val appCache: AppCache = AppCache(appContext.cacheDir)

    val httpClient: OkHttpClient = OkHttpClient()

    val serverUrlManager: ServerUrlManager = ServerUrlManager(keyValueStore, httpClient)

    val groupStore: GroupStore = GroupStore(appCache)
    val feedStore: FeedStore = FeedStore(appCache)
    val articleStore: ArticleStore = ArticleStore(appCache, keyValueStore, scope)
    val settingsStore: SettingsStore = SettingsStore()
    val stockStore: StockStore = StockStore(appCache, keyValueStore, scope)

    /// resolvedUrl が確定するたびに呼ぶ。5 Store の ApiClient を再設定し、全フェッチを開始する
    /// （iOS GogaiApp.configureStores 相当）。
    fun configureStores(baseUrl: HttpUrl) {
        // Why: 接続失敗（トンネル URL 失効など）を検知したら ServerUrlManager に再解決を促す。
        // デバウンス + resolve 成功時の自動更新により復旧する。
        val client = ApiClient(
            baseUrl = baseUrl,
            httpClient = httpClient,
            onNetworkFailure = { scope.launch { serverUrlManager.reportFailure() } },
        )
        groupStore.configure(client)
        feedStore.configure(client, onRefreshComplete = { scope.launch { articleStore.refresh() } })
        articleStore.configure(client)
        settingsStore.configure(client, secretStore)
        stockStore.configure(client)

        // Why: 4 系統は互いに独立した API のため並列に投げて起動時の待ち時間を短縮する
        // （iOS GogaiApp.configureStores が Task を複数投げて並列化しているのと同じ狙い）。
        scope.launch { groupStore.fetchGroups() }
        scope.launch { feedStore.fetchFeeds() }
        scope.launch {
            articleStore.fetchArticles()
            // バッジ用のサーバー集計（シークレット込み・1 リクエスト）を最新化する
            articleStore.refreshCounts()
        }
        scope.launch {
            stockStore.fetchAll()
            // アプリが要約処理中に終了していた場合、永続化されたキューを再開する
            stockStore.resumePersistedSummaryQueueIfNeeded()
            // 前回起動時の要約エラー（赤いビックリマーク表示用）を復元する
            stockStore.restorePersistedSummaryErrorsIfNeeded()
        }

        refreshAiWiring()
    }

    // MARK: - AI 配線（Phase 5）
    //
    // Gogai Android は AI をリモート API（OpenAI/Gemini/Claude）のみで提供する
    // （iOS の Foundation Models オンデバイス部分は移植しない）。
    // 設定値（AiProvider の選択 + APIキー）は都度 KeyValueStore/SecretStore から読み直すため、
    // 設定画面での変更は次に呼ばれる generate() 呼び出しから即反映される（アプリ再起動不要）。

    /**
     * 現在の設定から TextGenerating を解決する。呼び出しのたびに毎回解決するため、
     * 設定変更が次回呼び出しから即反映される（iOS LocalAI.makeGenerator() 相当。
     * Android はオンデバイス AI を持たないためリモートのみ）。キー未設定なら null。
     */
    fun currentTextGenerator(): TextGenerating? {
        val resolved = currentAiProvider(keyValueStore).resolve(secretStore) ?: return null
        val apiKey = resolved.apiKey(secretStore) ?: return null
        return RemoteAITextGenerator(provider = resolved, apiKey = apiKey)
    }

    /** 現在解決される AI プロバイダの表示ラベル（進捗ログ用）。未解決時は "AI"。 */
    fun currentAiProviderLabel(): String = currentAiProvider(keyValueStore).resolve(secretStore)?.label ?: "AI"

    /** 現時点でキーが1つでも設定済みか（呼び出し時点で毎回評価する）。 */
    fun aiAvailable(): Boolean = currentTextGenerator() != null

    /**
     * StockStore.summarizer を現在のキー設定に合わせて再評価し、配線し直す。
     * ui/stocks 側は `stockStore.summarizer != null` を aiAvailable の判定に使っているため、
     * この関数を呼ぶとストック一覧などの AI 表示が更新される。configureStores() で一度呼ぶほか、
     * 設定画面で API キーを保存した後にも呼べるよう公開している（呼び出し時評価の関数として提供）。
     */
    fun refreshAiWiring() {
        stockStore.summarizer = if (aiAvailable()) {
            StockSummarizing { stock, onProgress ->
                val generator = currentTextGenerator() ?: throw AiError.AiUnavailable
                val summarizer = StockSummarizer(
                    generator = generator,
                    providerLabel = currentAiProviderLabel(),
                    progress = onProgress,
                )
                summarizer.summarize(url = stock.url, title = stock.title, httpClient = httpClient)
            }
        } else {
            null
        }
    }
}
