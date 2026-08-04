package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.KeyValueStore
import com.mtkg.gogai.model.Article
import com.mtkg.gogai.model.ArticleSortOrder
import com.mtkg.gogai.model.FeedCount
import com.mtkg.gogai.model.FieldUpdate
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.repository.ArticleRepository
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/// 記事一覧・未読バッジ・既読状態の楽観更新を担う中心的な Store（iOS ArticleStore の移植）。
///
/// iOS の `@MainActor` 相当のスレッド閉じ込めは、呼び出し側が Dispatchers.Main.immediate 前提の
/// [scope] からこの Store のすべての suspend 関数を呼ぶことで担保する。内部状態
/// （fetchGeneration/pendingReadIds/loadingTaskCount 等）はロックなしの平フィールドでよい。
class ArticleStore(
    private val cache: AppCache,
    private val keyValueStore: KeyValueStore,
    private val scope: CoroutineScope,
    private val nowIso: () -> String = ::isoNowSeconds,
) {
    private val _articles = MutableStateFlow<List<Article>>(emptyList())
    val articles: StateFlow<List<Article>> = _articles.asStateFlow()

    /// 全フィードの記事キャッシュ（未読バッジの計算に使用）。
    /// articles はフィルタ表示用なので特定フィードのみになることがあるが、
    /// collection は常に全体を保持して未読カウントを正確にする。
    /// 更新は必ず mutateBoth / merge 経由で行い、articles との手動二重更新をしない。
    private val collection = ArticleCollection()
    private val _allArticles = MutableStateFlow<List<Article>>(emptyList())
    val allArticles: StateFlow<List<Article>> = _allArticles.asStateFlow()

    /// フィードごとのサーバー集計（GET /api/articles/counts）。バッジ計算の第一ソース。
    /// 空（未取得）のときは allArticles ベースの計算にフォールバックする。
    private val _feedCounts = MutableStateFlow<Map<Int, FeedCount>>(emptyMap())
    val feedCounts: StateFlow<Map<Int, FeedCount>> = _feedCounts.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()

    private val _unreadOnly = MutableStateFlow(keyValueStore.getBoolean(DefaultsKeys.UNREAD_ONLY, false))
    val unreadOnly: StateFlow<Boolean> = _unreadOnly.asStateFlow()

    private val _sortOrder = MutableStateFlow(
        ArticleSortOrder.fromRawValue(keyValueStore.getString(DefaultsKeys.SORT_ORDER)) ?: ArticleSortOrder.PublishedAt
    )
    val sortOrder: StateFlow<ArticleSortOrder> = _sortOrder.asStateFlow()

    private var client: ApiClient? = null
    private var currentFeedId: Int? = null
    private var currentGroupId: Int? = null
    private var currentIncludeSecret: Boolean = false

    /// markAsRead API 呼び出しがネットワーク障害で失敗した記事 ID セット。
    /// - 対象: IOException（サーバー再起動・圏外など）のみ。4xx 等は対象外
    /// - スコープ: インメモリのみ。アプリを強制終了・再起動すると消える
    /// - 次回 fetchArticles 成功時に applyPendingReads() で UI を復元し再送する
    private val pendingReadIds = mutableSetOf<Int>()

    /// 最後の fetchArticles が unreadOnly=true で実行されたかどうか。
    /// refresh() での既読記事保持の判定に使用する。
    private var loadedWithUnreadOnly = false

    /// 並行する fetchArticles 呼び出しで古い結果が上書きしないよう管理する世代カウンター
    private var fetchGeneration = 0

    /// isLoading を正確に管理するための実行中タスク数
    private var loadingTaskCount = 0

    init {
        // 起動時にキャッシュから全記事を読み込み、未読カウントを即座に表示する
        collection.replaceAll(cache.loadAllArticles())
        _allArticles.value = collection.articles
        _feedCounts.value = indexed(cache.loadFeedCounts())
    }

    fun configure(client: ApiClient) {
        this.client = client
    }

    fun setUnreadOnly(value: Boolean) {
        _unreadOnly.value = value
        keyValueStore.putBoolean(DefaultsKeys.UNREAD_ONLY, value)
    }

    fun setSortOrder(value: ArticleSortOrder) {
        _sortOrder.value = value
        keyValueStore.putString(DefaultsKeys.SORT_ORDER, value.rawValue)
    }

    suspend fun fetchArticles(
        feedId: Int? = null,
        groupId: Int? = null,
        unreadOnly: Boolean? = null,
        includeSecret: Boolean = false,
    ) {
        val client = this.client ?: return
        currentFeedId = feedId
        currentGroupId = groupId
        currentIncludeSecret = includeSecret
        if (unreadOnly != null) setUnreadOnly(unreadOnly)
        fetchGeneration += 1
        val myGeneration = fetchGeneration
        loadingTaskCount += 1
        _isLoading.value = true
        try {
            val fetched = ArticleRepository(client).fetchAll(
                feedId = feedId,
                groupId = groupId,
                unreadOnly = _unreadOnly.value,
                sortOrder = _sortOrder.value,
                includeSecret = includeSecret,
            )
            // 新しいフェッチが始まっていれば古い結果は破棄する
            if (myGeneration != fetchGeneration) return
            _articles.value = fetched
            loadedWithUnreadOnly = _unreadOnly.value
            // コレクション（未読バッジ・サイドバー表示判定用）は全記事が必要。
            // unreadOnly のフィルターが有効なフェッチ結果は一部の記事しか含まないため、
            // これで上書きするとキャッシュが汚染される。フィルターなしの全件フェッチ時のみ更新する。
            if (!_unreadOnly.value) {
                collection.merge(fetched, isFullFetch = feedId == null && groupId == null)
                _allArticles.value = collection.articles
                cache.saveAllArticles(collection.articles)
            }
            // サーバーに届かなかった既読状態をローカルに復元し、バックグラウンドで再送する
            if (pendingReadIds.isNotEmpty()) {
                applyPendingReads()
                scope.launch { retryPendingMarkAsRead() }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (myGeneration == fetchGeneration) _error.value = e
        } finally {
            loadingTaskCount -= 1
            if (loadingTaskCount == 0) _isLoading.value = false
        }
    }

    suspend fun refresh() {
        // refresh 前に既読になっていた記事を保存する
        // unreadOnly=true かつ前回フェッチも unreadOnly=true だった場合のみ保存する
        // （unreadOnly=false で読み込まれた記事は既読・未読が混在しており、
        //   「このセッションで読んだ記事」と区別できないため保持しない）
        val previouslyReadArticles = if (loadedWithUnreadOnly) _articles.value.filter { it.isRead } else emptyList()

        // refresh 開始時の世代を記録し、fetch 中に外部から fetchArticles が呼ばれたか検知する
        val genBefore = fetchGeneration
        fetchArticles(feedId = currentFeedId, groupId = currentGroupId, includeSecret = currentIncludeSecret)

        // バッジ用のサーバー集計は表示中フィードに関わらずグローバルに更新する
        // （特定フィード表示中でも他フィードの新着がバッジに反映されるように）
        refreshCounts()

        // 自分の fetchArticles 以外にも呼び出しがあった場合はその結果を尊重し保持ロジックをスキップ
        // （「全て→未読のみ」切り替えなど、ユーザー操作による最新フェッチを優先するため）
        if (fetchGeneration != genBefore + 1) return
        if (previouslyReadArticles.isEmpty()) return

        // API レスポンス遅延による未読状態の不一致を修正（fetch 結果に含まれている場合）
        val localReadIds = previouslyReadArticles.map { it.id }.toSet()
        val preserveReadState: (Article) -> Article = { a ->
            if (localReadIds.contains(a.id) && !a.isRead) a.updating(isRead = 1) else a
        }
        _articles.value = _articles.value.map(preserveReadState)
        collection.updateAll(preserveReadState)
        _allArticles.value = collection.articles

        // unreadOnly: true の場合、fetch 結果に含まれなかった既読記事をリストに保持する
        // （このセッションで読んだ記事が自動 refresh で消えないようにするため）
        // コレクションは未読バッジ計算用のため、既読になった記事は追加不要
        if (_unreadOnly.value) {
            val newIds = _articles.value.map { it.id }.toSet()
            val toPreserve = previouslyReadArticles.filter { it.id !in newIds }
            if (toPreserve.isNotEmpty()) {
                _articles.value = (_articles.value + toPreserve).sortedWith(articleDateComparator(_sortOrder.value))
            }
        }
    }

    /// 既読⇄未読を記事の現在状態に応じて切り替える（View 側の分岐重複を防ぐ）
    suspend fun toggleRead(article: Article) {
        if (article.isRead) markAsUnread(article.id) else markAsRead(article.id)
    }

    suspend fun markAsRead(id: Int) {
        val client = this.client ?: return
        val now = nowIso()
        optimisticUpdate(
            id = id,
            transform = { it.updating(isRead = 1, readAt = FieldUpdate.Set(now)) },
            apiCall = { ArticleRepository(client).markAsRead(id) },
            onIOException = UrlErrorPolicy.EnqueuePendingRead,
        )
    }

    suspend fun markAllAsRead() {
        val unread = _articles.value.filter { !it.isRead }
        val client = this.client ?: return
        if (unread.isEmpty()) return

        // Optimistic update（mutateBoth 経由で articles / コレクション / feedCounts を同期）
        val now = nowIso()
        for (article in unread) {
            mutateBoth(article.id) { it.updating(isRead = 1, readAt = FieldUpdate.Set(now)) }
        }

        // API calls: IOException → pending queue, others → rollback
        for (original in unread) {
            try {
                ArticleRepository(client).markAsRead(original.id)
                pendingReadIds.remove(original.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: IOException) {
                pendingReadIds.add(original.id)
            } catch (e: Exception) {
                mutateBoth(original.id) { original }
            }
        }

        // サーバー集計と突き合わせてバッジを確定させる（失敗時はローカル差分を維持）
        refreshCounts()
    }

    suspend fun markAsUnread(id: Int) {
        val client = this.client ?: return
        optimisticUpdate(
            id = id,
            transform = { it.updating(isRead = 0, readAt = FieldUpdate.Clear) },
            apiCall = { ArticleRepository(client).markAsUnread(id) },
            onIOException = UrlErrorPolicy.CancelPendingRead,
        )
    }

    // MARK: - バッジ件数・表示判定（現在のフィルタに連動）

    /// バッジ計算・表示判定に使う記事ソース。
    /// 全フィードキャッシュ（コレクション）を優先し、空のときだけ表示中リストにフォールバックする。
    private val badgeSource: List<Article>
        get() = if (collection.isEmpty) _articles.value else collection.articles

    /// 現在のフィルタ（全て / 未読のみ）に記事が合致するか
    private fun matchesCurrentFilter(article: Article): Boolean {
        if (_unreadOnly.value && article.isRead) return false
        return true
    }

    /// サーバー集計をバッジ計算に使えるか。未取得（空）のときはコレクション計算にフォールバックする。
    private val canUseFeedCounts: Boolean
        get() = _feedCounts.value.isNotEmpty()

    /// 現在のフィルタに対応する集計値。「全て」= total、「未読のみ」= unread
    private fun filteredCount(count: FeedCount): Int = if (_unreadOnly.value) count.unread else count.total

    /// 現在有効なフィルタ（unreadOnly）を適用したとき、
    /// 指定フィードに表示対象の記事が 1 件以上あるかを返す。
    /// フィルタが何も有効でない場合は常に true。
    fun hasVisibleArticle(feedId: Int): Boolean {
        if (!_unreadOnly.value) return true
        if (canUseFeedCounts) {
            return _feedCounts.value[feedId]?.let { filteredCount(it) > 0 } ?: false
        }
        return badgeSource.any { it.feed_id == feedId && matchesCurrentFilter(it) }
    }

    /// フィードのバッジ件数。「全て」=全記事数、「未読のみ」=未読数。feedId が null なら全フィード合計
    fun badgeCount(feedId: Int? = null): Int {
        if (canUseFeedCounts) {
            if (feedId == null) return _feedCounts.value.values.sumOf { filteredCount(it) }
            return _feedCounts.value[feedId]?.let { filteredCount(it) } ?: 0
        }
        val filtered = if (feedId != null) badgeSource.filter { it.feed_id == feedId } else badgeSource
        return filtered.count { matchesCurrentFilter(it) }
    }

    /// グループ（所属フィード群）のバッジ件数
    fun badgeCountForGroup(feedIds: List<Int>): Int {
        if (canUseFeedCounts) {
            return feedIds.sumOf { fid -> _feedCounts.value[fid]?.let { filteredCount(it) } ?: 0 }
        }
        val feedIdSet = feedIds.toSet()
        return badgeSource.count { it.feed_id in feedIdSet && matchesCurrentFilter(it) }
    }

    /// 「すべての記事」のバッジ件数（シークレットフィード除外用）
    fun badgeCountExcluding(feedIds: Set<Int>): Int {
        if (canUseFeedCounts) {
            return _feedCounts.value.values.sumOf { if (it.feed_id in feedIds) 0 else filteredCount(it) }
        }
        return badgeSource.count { it.feed_id !in feedIds && matchesCurrentFilter(it) }
    }

    /// サーバー集計（フィードごとの total/unread）を取得してバッジ計算を最新化する。
    /// ベストエフォート: 失敗時は前回値（起動時はディスクキャッシュ復元値）を維持し error を立てない。
    suspend fun refreshCounts() {
        val client = this.client ?: return
        val fetched = try {
            ArticleRepository(client).fetchCounts()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return
        }
        var counts = indexed(fetched)
        // pending（サーバーに届いていない既読）はサーバー集計に未反映のため減算して補正する
        for (id in pendingReadIds) {
            val article = collection.articles.firstOrNull { it.id == id } ?: _articles.value.firstOrNull { it.id == id } ?: continue
            val count = counts[article.feed_id] ?: continue
            counts = counts + (article.feed_id to count.copy(unread = maxOf(0, count.unread - 1)))
        }
        _feedCounts.value = counts
        cache.saveFeedCounts(fetched)
    }

    // MARK: - Private

    /// IOException（ネットワーク障害）発生時の振る舞い
    private enum class UrlErrorPolicy {
        /// 楽観更新を維持し、既読リトライキューに積む（markAsRead）
        EnqueuePendingRead,

        /// 楽観更新を維持し、既読リトライキューから取り除く（markAsUnread）
        CancelPendingRead,
    }

    /// 楽観的更新の唯一の経路。
    /// articles とコレクションを同一の変換で同期更新し、API 失敗時はロールバックする。
    private suspend fun optimisticUpdate(
        id: Int,
        transform: (Article) -> Article,
        apiCall: suspend () -> Unit,
        onIOException: UrlErrorPolicy,
    ) {
        val original = mutateBoth(id, transform) ?: return

        try {
            apiCall()
            pendingReadIds.remove(id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            when (onIOException) {
                UrlErrorPolicy.EnqueuePendingRead -> pendingReadIds.add(id)
                UrlErrorPolicy.CancelPendingRead -> pendingReadIds.remove(id)
            }
        } catch (e: Exception) {
            mutateBoth(id) { original }
            _error.value = e
        }
    }

    /// articles とコレクションの該当記事を同一の変換で更新する（同期漏れを構造的に防ぐ）。
    /// feedCounts にも既読状態の差分を反映する（ロールバックは逆変換で自動的に打ち消される）。
    /// @return 変換前の記事（articles に存在しない場合は null で何もしない）
    private fun mutateBoth(id: Int, transform: (Article) -> Article): Article? {
        val idx = _articles.value.indexOfFirst { it.id == id }
        if (idx < 0) return null
        val original = _articles.value[idx]
        val updated = transform(original)
        _articles.value = _articles.value.toMutableList().also { it[idx] = updated }
        collection.upsert(updated)
        _allArticles.value = collection.articles
        applyCountsDelta(original, updated)
        return original
    }

    /// 記事の変換前後の状態差分を feedCounts に反映する。
    /// counts に無い feed_id は無視する（サーバー集計との整合のため勝手に行を作らない）。
    private fun applyCountsDelta(original: Article, updated: Article) {
        val count = _feedCounts.value[original.feed_id] ?: return
        val unreadDelta = (if (updated.isRead) 0 else 1) - (if (original.isRead) 0 else 1)
        if (unreadDelta == 0) return
        _feedCounts.value = _feedCounts.value + (original.feed_id to count.copy(unread = maxOf(0, count.unread + unreadDelta)))
    }

    /// pendingReadIds に含まれる記事をローカルで既読に上書きする（fetchArticles 後に呼ぶ）
    private fun applyPendingReads() {
        if (pendingReadIds.isEmpty()) return
        val now = nowIso()
        val apply: (Article) -> Article = { article ->
            if (pendingReadIds.contains(article.id)) article.markingAsRead(now) else article
        }
        _articles.value = _articles.value.map(apply)
        collection.updateAll(apply)
        _allArticles.value = collection.articles
    }

    /// pendingReadIds の記事に対してサーバーへ markAsRead を再送する
    private suspend fun retryPendingMarkAsRead() {
        val client = this.client ?: return
        if (pendingReadIds.isEmpty()) return
        val idsToRetry = pendingReadIds.toList()
        for (id in idsToRetry) {
            // 再送ループ中に markAsUnread が呼ばれてキューから除去された ID はスキップ
            if (!pendingReadIds.contains(id)) continue
            try {
                ArticleRepository(client).markAsRead(id)
                pendingReadIds.remove(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 再送失敗 - 次回 fetchArticles で再試行
            }
        }
    }

    companion object {
        private fun indexed(counts: List<FeedCount>): Map<Int, FeedCount> = counts.associateBy { it.feed_id }

        private fun articleDateComparator(sortOrder: ArticleSortOrder): Comparator<Article> = Comparator { a, b ->
            when (sortOrder) {
                ArticleSortOrder.PublishedAt -> {
                    val aDate = a.published_at ?: a.created_at
                    val bDate = b.published_at ?: b.created_at
                    bDate.compareTo(aDate)
                }
                ArticleSortOrder.ReadAt -> {
                    val aDate = a.read_at ?: a.published_at ?: a.created_at
                    val bDate = b.read_at ?: b.published_at ?: b.created_at
                    bDate.compareTo(aDate)
                }
            }
        }
    }
}
