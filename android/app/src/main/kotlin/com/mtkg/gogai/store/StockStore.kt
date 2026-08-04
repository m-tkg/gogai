package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.KeyValueStore
import com.mtkg.gogai.model.FieldUpdate
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.model.StockCategory
import com.mtkg.gogai.model.StockTranslationPayload
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.ApiException
import com.mtkg.gogai.repository.StockRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/// SummaryQueue が実際の要約生成処理を委譲する先。Phase 5 で TextGenerator ベースの実装を注入する
/// （iOS の `any TextGenerating` に相当する差し替えポイント。まだ実装が無いため仮の抽象として定義する）。
fun interface StockSummarizing {
    suspend fun summarize(stock: Stock, onProgress: (String) -> Unit): String
}

/// ストック一覧・要約キュー・翻訳を保持する Store（iOS StockStore の移植）。
class StockStore(
    private val cache: AppCache,
    private val keyValueStore: KeyValueStore,
    private val scope: CoroutineScope,
) {
    private val _categories = MutableStateFlow<List<StockCategory>>(cache.loadStockCategories())
    val categories: StateFlow<List<StockCategory>> = _categories.asStateFlow()

    private val _stocks = MutableStateFlow<List<Stock>>(cache.loadStocks())
    val stocks: StateFlow<List<Stock>> = _stocks.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()

    private val _sortAscending = MutableStateFlow(keyValueStore.getBoolean(DefaultsKeys.STOCK_SORT_ASCENDING, false))
    val sortAscending: StateFlow<Boolean> = _sortAscending.asStateFlow()

    fun setSortAscending(value: Boolean) {
        _sortAscending.value = value
        keyValueStore.putBoolean(DefaultsKeys.STOCK_SORT_ASCENDING, value)
    }

    /// テスト用/Phase 5 用の差し替えポイント。未設定（null）の間は要約生成が即エラーになる。
    var summarizer: StockSummarizing? = null

    // MARK: - 要約キュー
    // 実体は SummaryQueue が保持する（状態変数・実行ロジック・レースコンディション回避のための
    // 手動同期はすべてそちら参照）。View のライフサイクルに依存せず Store が持ち続けるため、
    // 画面遷移後もキュー処理を継続できる。ここでは SummaryQueue からの通知を StateFlow へミラーし、
    // KeyValueStore への永続化を行う薄い consumer にする。

    private val _pendingSummaryStockIds = MutableStateFlow<List<Int>>(emptyList())
    val pendingSummaryStockIds: StateFlow<List<Int>> = _pendingSummaryStockIds.asStateFlow()

    private val _currentlySummarizingStockId = MutableStateFlow<Int?>(null)
    val currentlySummarizingStockId: StateFlow<Int?> = _currentlySummarizingStockId.asStateFlow()

    private val _summaryErrors = MutableStateFlow<Map<Int, String>>(emptyMap())
    val summaryErrors: StateFlow<Map<Int, String>> = _summaryErrors.asStateFlow()

    /// ストックIDごとの要約生成ログ。生成中画面で直近の処理内容を表示する。
    private val _summaryProgressLogs = MutableStateFlow<Map<Int, List<String>>>(emptyMap())
    val summaryProgressLogs: StateFlow<Map<Int, List<String>>> = _summaryProgressLogs.asStateFlow()

    private val _isSummaryQueuePausedByUser = MutableStateFlow(false)
    val isSummaryQueuePausedByUser: StateFlow<Boolean> = _isSummaryQueuePausedByUser.asStateFlow()

    private val summaryQueue = SummaryQueue(scope)

    private var client: ApiClient? = null

    init {
        summaryQueue.performSummary = { stockId -> generateSummary(stockId) }
        summaryQueue.onChange = { syncSummaryQueueState() }
    }

    fun configure(client: ApiClient) {
        this.client = client
    }

    /// 指定カテゴリのストックを stocked_at でソートして返す（sortAscending に連動）
    fun stocksIn(categoryId: Int): List<Stock> {
        val filtered = _stocks.value.filter { it.category_id == categoryId }
        return if (_sortAscending.value) filtered.sortedBy { it.stocked_at } else filtered.sortedByDescending { it.stocked_at }
    }

    suspend fun fetchAll() {
        val client = this.client ?: return
        _isLoading.value = true
        try {
            coroutineScope {
                val categoriesDeferred = async { StockRepository(client).fetchCategories() }
                val stocksDeferred = async { StockRepository(client).fetchAll() }
                _categories.value = categoriesDeferred.await()
                _stocks.value = stocksDeferred.await()
            }
            cache.saveStockCategories(_categories.value)
            cache.saveStocks(_stocks.value)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.value = e
        } finally {
            _isLoading.value = false
        }
    }

    /// URL が既にストック済みの場合はサーバー側で no-op になる（既存を返す）。
    /// 戻り値のストックをローカルへ反映する。失敗時は throw する（呼び出し元がエラー表示 or 黙殺を選ぶ）。
    suspend fun createStock(url: String, title: String? = null, source: String? = null, category: String? = null): Stock {
        val client = this.client ?: throw ApiException.InvalidUrl()
        val stock = StockRepository(client).create(url, title, source, category)
        upsertLocally(stock)
        return stock
    }

    suspend fun updateStock(id: Int, title: String, category: String) {
        val client = this.client ?: return
        val updated = StockRepository(client).update(id, title, category)
        upsertLocally(updated)
        removeEmptyCategoriesLocally()
    }

    suspend fun deleteStock(id: Int) {
        val client = this.client ?: return
        StockRepository(client).delete(id)
        _stocks.value = _stocks.value.filterNot { it.id == id }
        _summaryErrors.value = _summaryErrors.value - id
        removeEmptyCategoriesLocally()
    }

    suspend fun saveSummary(id: Int, summary: String) {
        val client = this.client ?: return
        StockRepository(client).saveSummary(id, summary)
        val idx = _stocks.value.indexOfFirst { it.id == id }
        if (idx >= 0) {
            _stocks.value = _stocks.value.toMutableList().also {
                it[idx] = it[idx].updating(summary = FieldUpdate.Set(summary))
            }
        }
    }

    /// 保存済みの翻訳を取得する（未保存・取得失敗時は null）
    suspend fun fetchTranslation(id: Int): StockTranslationPayload? {
        val client = this.client ?: return null
        return try {
            StockRepository(client).fetchTranslation(id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
    }

    /// 翻訳を保存する（UPSERT。再翻訳時の上書きもこのメソッドを使う）
    suspend fun saveTranslation(id: Int, segments: String) {
        val client = this.client ?: return
        StockRepository(client).saveTranslation(id, segments)
        val idx = _stocks.value.indexOfFirst { it.id == id }
        if (idx >= 0) {
            _stocks.value = _stocks.value.toMutableList().also {
                it[idx] = it[idx].updating(hasTranslation = true)
            }
        }
    }

    /// 指定したストック 1 件の要約を生成して保存する。ユーザーの明示的なボタン操作、または
    /// SummaryQueue からのみ呼ばれる。summarizer が未設定（Phase 5 の TextGenerator 未実装）
    /// の間は summaryErrors へ即エラーを記録した上で throw する。
    suspend fun generateSummary(stockId: Int) {
        val stock = _stocks.value.firstOrNull { it.id == stockId } ?: return
        val summarizer = this.summarizer
        if (summarizer == null) {
            val message = "要約機能が利用できません"
            recordSummaryError(stockId, message)
            throw IllegalStateException(message)
        }
        resetSummaryProgressLog(stockId, "要約処理を開始")
        val summary = summarizer.summarize(stock) { message -> appendSummaryProgressLog(stockId, message) }
        appendSummaryProgressLog(stockId, "生成した要約をサーバーへ保存中")
        saveSummary(stockId, summary)
        appendSummaryProgressLog(stockId, "要約の保存が完了")
    }

    /// 要約をキューに追加する（fire-and-forget）。View のライフサイクル（戻るボタン等）に
    /// 依存せず Store が保持し続けるため、画面遷移後もキュー処理を継続する。
    /// 既に生成中/待機中のストックは無視する。生成済みのストックは force: true のときだけ
    /// 再生成を受け付ける（呼び出し側で上書き確認を取ってから呼ぶこと）。
    fun requestSummary(stockId: Int, force: Boolean = false) {
        val alreadySummarized = _stocks.value.firstOrNull { it.id == stockId }?.summary != null
        if (!force && alreadySummarized) return
        resetSummaryProgressLog(stockId, "要約キューに追加")
        summaryQueue.enqueue(stockId)
    }

    /// 翻訳を優先させるため、実行中の要約があれば中断してキュー処理を一時停止する。
    fun pauseSummaryQueueForTranslation() {
        summaryQueue.pauseForTranslation()
    }

    /// 翻訳完了後、要約キューを再開する。ユーザーが一時停止中の場合は再開しない。
    fun resumeSummaryQueueAfterTranslation() {
        summaryQueue.resumeAfterTranslation()
    }

    /// ユーザー操作による一時停止。実行中の要約があれば中断し、キュー先頭へ戻す（やり直せるように）。
    fun pauseSummaryQueue() {
        summaryQueue.pauseByUser()
    }

    /// ユーザー操作による一時停止を解除する。
    fun resumeSummaryQueue() {
        summaryQueue.resumeByUser()
    }

    /// キュー内の特定のストックをキャンセルする。
    fun cancelSummary(stockId: Int) {
        summaryQueue.cancel(stockId)
    }

    /// エラーアラートを閉じた後の表示クリア用。
    fun clearSummaryError(stockId: Int) {
        summaryQueue.clearError(stockId)
    }

    /// アプリ再起動時に、永続化された要約キューを再開する。fetchAll() で stocks を
    /// 読み込んだ後に呼ぶこと。既に要約済み/削除済みのストック ID は除外する。
    fun resumePersistedSummaryQueueIfNeeded() {
        val persistedIds = loadPersistedIntList(DefaultsKeys.STOCK_SUMMARY_QUEUE)
        val restoredIds = persistedIds.filter { id ->
            _stocks.value.firstOrNull { it.id == id }?.summary == null
        }
        summaryQueue.restorePending(restoredIds)
    }

    /// アプリ再起動時に、永続化された要約エラーを復元する。fetchAll() で stocks を
    /// 読み込んだ後に呼ぶこと。削除済み・他端末で要約成功済みのストックは除外する。
    fun restorePersistedSummaryErrorsIfNeeded() {
        val stored = loadPersistedStringMap(DefaultsKeys.STOCK_SUMMARY_ERRORS)
        val restored = stored.mapNotNull { (key, value) ->
            val id = key.toIntOrNull() ?: return@mapNotNull null
            val stock = _stocks.value.firstOrNull { it.id == id } ?: return@mapNotNull null
            if (stock.summary != null) return@mapNotNull null
            id to value
        }.toMap()
        summaryQueue.restoreErrors(restored)
    }

    suspend fun reorderCategories(from: Int, to: Int) {
        val client = this.client ?: return
        _categories.value = reorderAndPersist(_categories.value, from, to, { it.id }) { ids ->
            StockRepository(client).reorderCategories(ids)
        }
    }

    // MARK: - Private

    private fun recordSummaryError(stockId: Int, message: String) {
        _summaryErrors.value = _summaryErrors.value + (stockId to message)
        persistSummaryErrorsSnapshot()
    }

    /// 現在の要約キュー（生成中 + 待機中）を KeyValueStore へ保存する。
    /// アプリ強制終了後も resumePersistedSummaryQueueIfNeeded() で再開できるようにするため。
    private fun persistSummaryQueueSnapshot() {
        val snapshot = (_currentlySummarizingStockId.value?.let { listOf(it) } ?: emptyList()) + _pendingSummaryStockIds.value
        keyValueStore.putString(DefaultsKeys.STOCK_SUMMARY_QUEUE, Json.encodeToString(ListSerializer(Int.serializer()), snapshot))
    }

    /// summaryErrors（ストックIDごとの直近の要約失敗メッセージ）を KeyValueStore へ保存する。
    /// アプリ再起動後もカテゴリ一覧・ストック一覧の赤いビックリマーク表示を維持するため。
    private fun persistSummaryErrorsSnapshot() {
        val stringKeyed = _summaryErrors.value.mapKeys { it.key.toString() }
        keyValueStore.putString(
            DefaultsKeys.STOCK_SUMMARY_ERRORS,
            Json.encodeToString(MapSerializer(String.serializer(), String.serializer()), stringKeyed),
        )
    }

    private fun loadPersistedIntList(key: String): List<Int> {
        val raw = keyValueStore.getString(key) ?: return emptyList()
        return try {
            Json.decodeFromString(ListSerializer(Int.serializer()), raw)
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun loadPersistedStringMap(key: String): Map<String, String> {
        val raw = keyValueStore.getString(key) ?: return emptyMap()
        return try {
            Json.decodeFromString(MapSerializer(String.serializer(), String.serializer()), raw)
        } catch (e: Exception) {
            emptyMap()
        }
    }

    /// SummaryQueue の状態を StateFlow へミラーする（onChange から呼ばれる）。
    private fun syncSummaryQueueState() {
        _pendingSummaryStockIds.value = summaryQueue.pending
        _currentlySummarizingStockId.value = summaryQueue.currentlySummarizing
        _summaryErrors.value = summaryQueue.errors
        _isSummaryQueuePausedByUser.value = summaryQueue.isPausedByUser
        persistSummaryQueueSnapshot()
        persistSummaryErrorsSnapshot()
    }

    private fun resetSummaryProgressLog(stockId: Int, firstMessage: String) {
        _summaryProgressLogs.value = _summaryProgressLogs.value + (stockId to listOf(firstMessage))
    }

    private fun appendSummaryProgressLog(stockId: Int, message: String) {
        val logs = (_summaryProgressLogs.value[stockId] ?: emptyList()) + message
        _summaryProgressLogs.value = _summaryProgressLogs.value + (stockId to logs.takeLast(50))
    }

    private fun upsertLocally(stock: Stock) {
        val idx = _stocks.value.indexOfFirst { it.id == stock.id }
        _stocks.value = if (idx >= 0) {
            _stocks.value.toMutableList().also { it[idx] = stock }
        } else {
            _stocks.value + stock
        }
        if (_categories.value.none { it.id == stock.category_id }) {
            // カテゴリがまだローカルにない（新規作成された）場合は一覧を取り直す
            scope.launch { refreshCategories() }
        }
    }

    private suspend fun refreshCategories() {
        val client = this.client ?: return
        _categories.value = try {
            StockRepository(client).fetchCategories()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _categories.value
        }
    }

    /// ストックが 0 件になったカテゴリはサーバー側で自動削除されるため、ローカル一覧も同期する
    private suspend fun removeEmptyCategoriesLocally() {
        refreshCategories()
    }
}
