package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.FieldUpdate
import com.mtkg.gogai.model.RefreshResult
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.ApiException
import com.mtkg.gogai.repository.FeedRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/// フィード一覧を保持する Store（iOS FeedStore の移植）
class FeedStore(private val cache: AppCache) {
    private val _feeds = MutableStateFlow<List<Feed>>(cache.loadFeeds())
    val feeds: StateFlow<List<Feed>> = _feeds.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()

    private var client: ApiClient? = null
    private var onRefreshComplete: (() -> Unit)? = null

    fun configure(client: ApiClient, onRefreshComplete: (() -> Unit)? = null) {
        this.client = client
        this.onRefreshComplete = onRefreshComplete
    }

    suspend fun fetchFeeds() {
        val client = this.client ?: return
        _isLoading.value = true
        try {
            val fetched = FeedRepository(client).fetchAll()
            _feeds.value = fetched
            cache.saveFeeds(fetched)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.value = e
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun createFeed(url: String, groupId: Int? = null) {
        val client = this.client ?: return
        val newFeed = FeedRepository(client).create(url, groupId)
        _feeds.value = _feeds.value + newFeed
    }

    suspend fun updateFeed(id: Int, title: String? = null, groupId: FieldUpdate<Int> = FieldUpdate.Keep) {
        val client = this.client ?: return
        val updated = FeedRepository(client).update(id, title, groupId)
        val idx = _feeds.value.indexOfFirst { it.id == id }
        if (idx >= 0) {
            _feeds.value = _feeds.value.toMutableList().also { it[idx] = updated }
        }
    }

    suspend fun deleteFeed(id: Int) {
        val client = this.client ?: return
        FeedRepository(client).delete(id)
        _feeds.value = _feeds.value.filterNot { it.id == id }
    }

    suspend fun refreshFeed(id: Int): RefreshResult {
        val client = this.client ?: throw ApiException.InvalidUrl()
        val result = FeedRepository(client).refresh(id)
        onRefreshComplete?.invoke()
        return result
    }

    suspend fun refreshAll(): RefreshResult {
        val client = this.client ?: throw ApiException.InvalidUrl()
        _isRefreshing.value = true
        try {
            val result = FeedRepository(client).refreshAll()
            onRefreshComplete?.invoke()
            return result
        } finally {
            _isRefreshing.value = false
        }
    }

    fun feeds(groupId: Int?): List<Feed> =
        if (groupId != null) _feeds.value.filter { it.group_id == groupId } else _feeds.value

    suspend fun reorderFeeds(from: Int, to: Int, groupId: Int?) {
        val client = this.client ?: return
        // feeds(groupId = null) は全フィードを返すため、group_id で直接フィルタする
        val groupFeeds = _feeds.value.filter { it.group_id == groupId }
        val otherFeeds = _feeds.value.filter { it.group_id != groupId }
        val reordered = reorderAndPersist(groupFeeds, from, to, { it.id }) { ids ->
            FeedRepository(client).reorder(ids)
        }
        _feeds.value = otherFeeds + reordered
    }
}
