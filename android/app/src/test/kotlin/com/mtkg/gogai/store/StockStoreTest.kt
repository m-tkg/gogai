package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.InMemoryKeyValueStore
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.model.StockCategory
import com.mtkg.gogai.network.ApiClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/// (method, path) ごとに独立した FIFO キューでレスポンスを返す Dispatcher。
/// StockStore.fetchAll() は categories/stocks を async で並行フェッチするため、
/// 単純な MockWebServer の単一キュー（enqueue）だと到着順序次第でレスポンスの
/// 取り違えが起き得る。エンドポイントごとにキューを分離することで順序非依存にする。
private class RoutingDispatcher : Dispatcher() {
    private val queues = mutableMapOf<String, ArrayDeque<MockResponse>>()

    fun enqueue(method: String, path: String, response: MockResponse) {
        queues.getOrPut(key(method, path)) { ArrayDeque() }.addLast(response)
    }

    override fun dispatch(request: RecordedRequest): MockResponse {
        val path = request.path?.substringBefore('?') ?: ""
        val method = request.method ?: "GET"
        val queue = queues[key(method, path)]
        return if (queue != null && queue.isNotEmpty()) {
            queue.removeFirst()
        } else {
            MockResponse().setResponseCode(404).setBody("no stub for $method $path")
        }
    }

    private fun key(method: String, path: String) = "$method $path"
}

@OptIn(ExperimentalCoroutinesApi::class)
class StockStoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var server: MockWebServer
    private lateinit var routing: RoutingDispatcher
    private lateinit var keyValueStore: InMemoryKeyValueStore
    private lateinit var storeScope: CoroutineScope
    private lateinit var store: StockStore

    private fun makeStock(
        id: Int,
        categoryId: Int = 1,
        categoryName: String = "Default",
        summary: String? = null,
        hasTranslation: Boolean = false,
        stockedAt: String = "2024-01-01T00:00:00Z",
    ) = Stock(
        id = id,
        url = "https://example.com/$id",
        title = "Title $id",
        source = "Group",
        category_id = categoryId,
        category_name = categoryName,
        summary = summary,
        has_translation = hasTranslation,
        stocked_at = stockedAt,
        created_at = "2024-01-01T00:00:00Z",
    )

    private fun makeCategory(id: Int, name: String = "Default", displayOrder: Int = 0, stockCount: Int = 0) =
        StockCategory(id = id, name = name, display_order = displayOrder, created_at = "2024-01-01T00:00:00Z", stock_count = stockCount)

    private fun newStore(cache: AppCache = AppCache(tempFolder.newFolder())): StockStore {
        val s = StockStore(cache, keyValueStore, storeScope)
        s.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))
        return s
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        server = MockWebServer()
        routing = RoutingDispatcher()
        server.dispatcher = routing
        server.start()
        keyValueStore = InMemoryKeyValueStore()
        // Why: SummaryQueue（ひいては StockStore）は Dispatchers.Main.immediate 相当の
        // 単一スレッド閉じ込めを前提にロックなしで実装されている。ここを実スレッド並列の
        // ディスパッチャにすると、テストからの呼び出し（enqueue/cancel 等）とバックグラウンド
        // 処理ループが別スレッドから同じ可変プロパティへ同期なしでアクセスすることになり、
        // 本来のプロダクション（Main.immediate）では起き得ないメモリ可視性のレースが生じる。
        // そのため storeScope も testDispatcher に紐付け、単一スレッド上で逐次実行させる。
        // 実ネットワーク I/O（MockWebServer/OkHttp の実スレッド）が絡む待ち合わせは
        // awaitUntil() 側で「ドレイン → 実時間で少し待つ → 再ドレイン」を繰り返して吸収する。
        storeScope = CoroutineScope(testDispatcher)
        store = newStore()
    }

    @After
    fun tearDown() {
        server.shutdown()
        Dispatchers.resetMain()
    }

    /// testDispatcher（単一スレッド）上のキュー処理が、実ネットワーク I/O（MockWebServer/OkHttp の
    /// 実スレッド）からの継続再開を待っている間に advanceUntilIdle() が先に返ってしまう問題を吸収する。
    /// 「仮想スケジューラをドレイン → 条件未成立なら実時間で少し待つ → 再ドレイン」を繰り返す。
    /// storeScope 自体は testDispatcher 上の単一スレッドで動くため、SummaryQueue のロックなし設計と
    /// 矛盾しない（複数スレッドから同時にプロパティへアクセスすることはない）。
    private suspend fun awaitUntil(timeoutMs: Long = 2_000, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (!condition()) {
            testDispatcher.scheduler.advanceUntilIdle()
            if (condition()) return
            if (System.currentTimeMillis() > deadline) {
                throw AssertionError("条件成立を待機中にタイムアウトした")
            }
            withContext(Dispatchers.IO) { Thread.sleep(2) }
        }
    }

    private fun enqueueCategories(categories: List<StockCategory>, code: Int = 200) {
        routing.enqueue(
            "GET",
            "/api/stock-categories",
            MockResponse().setResponseCode(code).setBody(Json.encodeToString(ListSerializer(StockCategory.serializer()), categories)),
        )
    }

    private fun enqueueStocksList(stocks: List<Stock>, code: Int = 200) {
        routing.enqueue(
            "GET",
            "/api/stocks",
            MockResponse().setResponseCode(code).setBody(Json.encodeToString(ListSerializer(Stock.serializer()), stocks)),
        )
    }

    private fun enqueueCreateStock(stock: Stock, code: Int = 200) {
        routing.enqueue("POST", "/api/stocks", MockResponse().setResponseCode(code).setBody(Json.encodeToString(Stock.serializer(), stock)))
    }

    private fun enqueueUpdateStock(id: Int, stock: Stock, code: Int = 200) {
        routing.enqueue("PUT", "/api/stocks/$id", MockResponse().setResponseCode(code).setBody(Json.encodeToString(Stock.serializer(), stock)))
    }

    private fun enqueueDeleteStock(id: Int, code: Int = 200) {
        routing.enqueue("DELETE", "/api/stocks/$id", MockResponse().setResponseCode(code))
    }

    private fun enqueueSaveSummary(id: Int, code: Int = 200) {
        routing.enqueue("PUT", "/api/stocks/$id/summary", MockResponse().setResponseCode(code))
    }

    private fun enqueueReorderCategories(code: Int = 200) {
        routing.enqueue("PATCH", "/api/stock-categories/reorder", MockResponse().setResponseCode(code))
    }

    /// fetchAll() が使う 2 エンドポイントをまとめて積む共通セットアップ
    private suspend fun fetchAllWith(categories: List<StockCategory>, stocks: List<Stock>) {
        enqueueCategories(categories)
        enqueueStocksList(stocks)
        store.fetchAll()
    }

    // MARK: - fetchAll

    @Test
    fun `fetchAll は categories と stocks を更新する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        assertEquals(1, store.categories.value.size)
        assertEquals(1, store.stocks.value.size)
        assertNull(store.error.value)
    }

    @Test
    fun `fetchAll は失敗時に error をセットする`() = runTest(testDispatcher) {
        enqueueCategories(emptyList(), code = 500)
        enqueueStocksList(emptyList(), code = 500)

        store.fetchAll()

        assertTrue(store.error.value != null)
    }

    // MARK: - createStock / updateStock / deleteStock

    @Test
    fun `createStock は stocks へ追加する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), emptyList())

        val newStock = makeStock(id = 5, categoryId = 1)
        enqueueCreateStock(newStock)

        val result = store.createStock(url = "https://example.com/5")

        assertEquals(5, result.id)
        assertEquals(1, store.stocks.value.size)
    }

    @Test
    fun `createStock は新しいカテゴリならカテゴリ一覧を再取得する`() = runTest(testDispatcher) {
        fetchAllWith(emptyList(), emptyList())

        val newStock = makeStock(id = 5, categoryId = 99, categoryName = "New")
        enqueueCreateStock(newStock)
        store.createStock(url = "https://example.com/5")

        enqueueCategories(listOf(makeCategory(id = 99, name = "New")))
        awaitUntil { store.categories.value.isNotEmpty() }

        assertEquals(1, store.categories.value.size)
        assertEquals(99, store.categories.value[0].id)
    }

    @Test
    fun `updateStock は stocks 内の該当要素を差し替える`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, categoryId = 1)))

        val updated = makeStock(id = 1, categoryId = 1).copy(title = "New Title")
        enqueueUpdateStock(1, updated)
        enqueueCategories(listOf(makeCategory(id = 1)))
        store.updateStock(id = 1, title = "New Title", category = "Default")

        assertEquals("New Title", store.stocks.value[0].title)
    }

    @Test
    fun `deleteStock は stocks から削除しエラーも消す`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        enqueueDeleteStock(1)
        enqueueCategories(emptyList())
        store.deleteStock(1)

        assertTrue(store.stocks.value.isEmpty())
    }

    // MARK: - stocksIn

    @Test
    fun `stocksIn はカテゴリでフィルタし stocked_at の降順で返す`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveStocks(
            listOf(
                makeStock(id = 1, categoryId = 1, stockedAt = "2024-01-01T00:00:00Z"),
                makeStock(id = 2, categoryId = 1, stockedAt = "2024-03-01T00:00:00Z"),
                makeStock(id = 3, categoryId = 2, stockedAt = "2024-02-01T00:00:00Z"),
            ),
        )
        val storeWithCache = StockStore(cache, keyValueStore, storeScope)

        val result = storeWithCache.stocksIn(1)

        assertEquals(listOf(2, 1), result.map { it.id })
    }

    @Test
    fun `stocksIn は sortAscending がtrueなら昇順で返す`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveStocks(
            listOf(
                makeStock(id = 1, categoryId = 1, stockedAt = "2024-01-01T00:00:00Z"),
                makeStock(id = 2, categoryId = 1, stockedAt = "2024-03-01T00:00:00Z"),
            ),
        )
        val storeWithCache = StockStore(cache, keyValueStore, storeScope)
        storeWithCache.setSortAscending(true)

        val result = storeWithCache.stocksIn(1)

        assertEquals(listOf(1, 2), result.map { it.id })
    }

    // MARK: - reorderCategories

    @Test
    fun `reorderCategories はローカル順序を更新する`() = runTest(testDispatcher) {
        fetchAllWith(
            listOf(makeCategory(id = 1, displayOrder = 0), makeCategory(id = 2, displayOrder = 1), makeCategory(id = 3, displayOrder = 2)),
            emptyList(),
        )

        enqueueReorderCategories()
        store.reorderCategories(from = 0, to = 3)

        assertEquals(listOf(2, 3, 1), store.categories.value.map { it.id })
    }

    // MARK: - generateSummary

    @Test
    fun `generateSummary は summarizer が null なら即エラーをsummaryErrorsへ記録しthrowする`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        var thrown = false
        try {
            store.generateSummary(1)
        } catch (e: IllegalStateException) {
            thrown = true
        }

        assertTrue(thrown)
        assertTrue(store.summaryErrors.value.containsKey(1))
    }

    @Test
    fun `generateSummary は成功時に要約を保存する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        store.summarizer = StockSummarizing { _, onProgress ->
            onProgress("生成中")
            "要約結果"
        }
        enqueueSaveSummary(1)

        store.generateSummary(1)

        assertEquals("要約結果", store.stocks.value.first { it.id == 1 }.summary)
        assertTrue(store.summaryProgressLogs.value[1]?.contains("生成中") == true)
    }

    @Test
    fun `generateSummary は失敗をthrowし保存しない`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        store.summarizer = StockSummarizing { _, _ -> throw RuntimeException("failed") }

        var thrown = false
        try {
            store.generateSummary(1)
        } catch (e: RuntimeException) {
            thrown = true
        }

        assertTrue(thrown)
        assertNull(store.stocks.value.first { it.id == 1 }.summary)
    }

    @Test
    fun `generateSummary は存在しないストックIDは何もしない`() = runTest(testDispatcher) {
        store.summarizer = StockSummarizing { _, _ -> "x" }
        store.generateSummary(999) // 例外を投げず静かに終わる
    }

    // MARK: - requestSummary（キュー経由）

    @Test
    fun `requestSummary はキューを介して要約を生成する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        store.summarizer = StockSummarizing { _, _ -> "要約" }
        enqueueSaveSummary(1)

        store.requestSummary(1)
        awaitUntil { store.stocks.value.first { it.id == 1 }.summary != null }

        assertEquals("要約", store.stocks.value.first { it.id == 1 }.summary)
        assertNull(store.currentlySummarizingStockId.value)
        assertTrue(store.pendingSummaryStockIds.value.isEmpty())
    }

    @Test
    fun `requestSummary は既に要約済みのストックは無視する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, summary = "既存の要約")))

        var called = false
        store.summarizer = StockSummarizing { _, _ -> called = true; "新しい要約" }

        store.requestSummary(1)
        // 要約済みストックはガードによりキューへ積まれず、非同期処理は一切走らない
        // （requestSummary がガードで即 return するため待機不要）。

        assertFalse(called)
    }

    @Test
    fun `requestSummary は force なら要約済みのストックも再生成する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, summary = "既存の要約")))

        store.summarizer = StockSummarizing { _, _ -> "新しい要約" }
        enqueueSaveSummary(1)

        store.requestSummary(1, force = true)
        awaitUntil { store.stocks.value.first { it.id == 1 }.summary == "新しい要約" }

        assertEquals("新しい要約", store.stocks.value.first { it.id == 1 }.summary)
    }

    @Test
    fun `requestSummary は2件目を1件目が完了するまで開始しない`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1), makeStock(id = 2)))

        val gate = CompletableDeferred<Unit>()
        val started = mutableListOf<Int>()
        store.summarizer = StockSummarizing { stock, _ ->
            started.add(stock.id)
            if (stock.id == 1) gate.await()
            "要約-${stock.id}"
        }
        enqueueSaveSummary(1)
        enqueueSaveSummary(2)

        store.requestSummary(1)
        store.requestSummary(2)
        awaitUntil { started.isNotEmpty() }

        assertEquals(listOf(1), started)
        assertEquals(1, store.currentlySummarizingStockId.value)
        assertEquals(listOf(2), store.pendingSummaryStockIds.value)

        gate.complete(Unit)
        awaitUntil { started.size == 2 }

        assertEquals(listOf(1, 2), started)
    }

    @Test
    fun `requestSummary は失敗しても次のキューへ進む`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1), makeStock(id = 2)))

        store.summarizer = StockSummarizing { stock, _ ->
            if (stock.id == 1) throw RuntimeException("failed")
            "要約-2"
        }
        enqueueSaveSummary(2) // id=1 は失敗するため保存は id=2 のみ

        store.requestSummary(1)
        store.requestSummary(2)
        awaitUntil { store.stocks.value.first { it.id == 2 }.summary != null }

        assertEquals("failed", store.summaryErrors.value[1])
        assertEquals("要約-2", store.stocks.value.first { it.id == 2 }.summary)
    }

    // MARK: - pause / resume / cancel / clearError（キュー委譲）

    @Test
    fun `pauseSummaryQueueForTranslation は実行中の要約を中断する`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        val gate = CompletableDeferred<Unit>()
        store.summarizer = StockSummarizing { _, _ -> gate.await(); "x" }

        store.requestSummary(1)
        awaitUntil { store.currentlySummarizingStockId.value == 1 }
        assertEquals(1, store.currentlySummarizingStockId.value)

        store.pauseSummaryQueueForTranslation()
        awaitUntil { store.currentlySummarizingStockId.value == null }

        assertNull(store.currentlySummarizingStockId.value)
        assertEquals(listOf(1), store.pendingSummaryStockIds.value)
    }

    @Test
    fun `cancelSummary は待機中のストックをキューから外す`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1), makeStock(id = 2)))

        val gate = CompletableDeferred<Unit>()
        store.summarizer = StockSummarizing { stock, _ -> if (stock.id == 1) gate.await(); "x" }

        store.requestSummary(1)
        // id:1 が実際に処理を開始する（pending から取り除かれる）のを待ってから2件目を積む。
        // でないと「1 が処理を開始する前に requestSummary(2) が呼ばれる」順序を保証できない。
        awaitUntil { store.currentlySummarizingStockId.value == 1 }
        store.requestSummary(2)
        store.cancelSummary(2)

        assertTrue(store.pendingSummaryStockIds.value.isEmpty())

        gate.complete(Unit)
        awaitUntil { store.currentlySummarizingStockId.value == null }
    }

    @Test
    fun `clearSummaryError は指定したストックのエラーだけ消す`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        store.summarizer = StockSummarizing { _, _ -> throw RuntimeException("boom") }
        store.requestSummary(1)
        awaitUntil { store.summaryErrors.value.containsKey(1) }

        assertTrue(store.summaryErrors.value.containsKey(1))

        store.clearSummaryError(1)

        assertFalse(store.summaryErrors.value.containsKey(1))
    }

    // MARK: - 永続化と復元

    @Test
    fun `sortAscending は KeyValueStore へ保存される`() {
        store.setSortAscending(true)
        assertTrue(keyValueStore.getBoolean(DefaultsKeys.STOCK_SORT_ASCENDING, false))
    }

    @Test
    fun `sortAscending の初期値はfalse`() {
        assertFalse(store.sortAscending.value)
    }

    @Test
    fun `要約が完了すると永続化キューから取り除かれる`() = runTest(testDispatcher) {
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1)))

        store.summarizer = StockSummarizing { _, _ -> "要約" }
        enqueueSaveSummary(1)

        store.requestSummary(1)
        awaitUntil { store.stocks.value.first { it.id == 1 }.summary != null }

        assertEquals(emptyList<Int>(), loadPersistedQueue())
    }

    @Test
    fun `resumePersistedSummaryQueueIfNeeded は永続化されたキューを再開する`() = runTest(testDispatcher) {
        keyValueStore.putString(DefaultsKeys.STOCK_SUMMARY_QUEUE, Json.encodeToString(ListSerializer(Int.serializer()), listOf(1)))
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, summary = null)))

        store.summarizer = StockSummarizing { _, _ -> "復元後の要約" }
        enqueueSaveSummary(1)

        store.resumePersistedSummaryQueueIfNeeded()
        awaitUntil { store.stocks.value.first { it.id == 1 }.summary != null }

        assertEquals("復元後の要約", store.stocks.value.first { it.id == 1 }.summary)
    }

    @Test
    fun `resumePersistedSummaryQueueIfNeeded は既に要約済みのIDは再開しない`() = runTest(testDispatcher) {
        keyValueStore.putString(DefaultsKeys.STOCK_SUMMARY_QUEUE, Json.encodeToString(ListSerializer(Int.serializer()), listOf(1)))
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, summary = "既存")))

        var called = false
        store.summarizer = StockSummarizing { _, _ -> called = true; "x" }

        store.resumePersistedSummaryQueueIfNeeded()
        // restorePending は ids が空（フィルタで除外済み）のときキューへ積まないため非同期処理は走らない

        assertFalse(called)
    }

    @Test
    fun `restorePersistedSummaryErrorsIfNeeded は要約未生成のストックのエラーを復元する`() = runTest(testDispatcher) {
        keyValueStore.putString(
            DefaultsKeys.STOCK_SUMMARY_ERRORS,
            Json.encodeToString(MapSerializer(String.serializer(), String.serializer()), mapOf("1" to "エラー")),
        )
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, summary = null)))

        store.restorePersistedSummaryErrorsIfNeeded()

        assertEquals("エラー", store.summaryErrors.value[1])
    }

    @Test
    fun `restorePersistedSummaryErrorsIfNeeded は要約済みのストックは復元しない`() = runTest(testDispatcher) {
        keyValueStore.putString(
            DefaultsKeys.STOCK_SUMMARY_ERRORS,
            Json.encodeToString(MapSerializer(String.serializer(), String.serializer()), mapOf("1" to "エラー")),
        )
        fetchAllWith(listOf(makeCategory(id = 1)), listOf(makeStock(id = 1, summary = "既に要約済み")))

        store.restorePersistedSummaryErrorsIfNeeded()

        assertNull(store.summaryErrors.value[1])
    }

    // MARK: - キャッシュ

    @Test
    fun `init はキャッシュから stocks categories を読み込む`() {
        val cache = AppCache(tempFolder.newFolder())
        cache.saveStocks(listOf(makeStock(id = 42)))
        cache.saveStockCategories(listOf(makeCategory(id = 7)))

        val storeWithCache = StockStore(cache, keyValueStore, storeScope)

        assertEquals(listOf(42), storeWithCache.stocks.value.map { it.id })
        assertEquals(listOf(7), storeWithCache.categories.value.map { it.id })
    }

    @Test
    fun `fetchAll はキャッシュへ保存する`() = runTest(testDispatcher) {
        val cache = AppCache(tempFolder.newFolder())
        val storeWithCache = StockStore(cache, keyValueStore, storeScope)
        storeWithCache.configure(ApiClient(baseUrl = server.url("/").toString().toHttpUrl()))

        enqueueCategories(listOf(makeCategory(id = 1)))
        enqueueStocksList(listOf(makeStock(id = 1)))
        storeWithCache.fetchAll()

        assertEquals(1, cache.loadStocks().size)
        assertEquals(1, cache.loadStockCategories().size)
    }

    private fun loadPersistedQueue(): List<Int> {
        val raw = keyValueStore.getString(DefaultsKeys.STOCK_SUMMARY_QUEUE) ?: return emptyList()
        return Json.decodeFromString(ListSerializer(Int.serializer()), raw)
    }
}
