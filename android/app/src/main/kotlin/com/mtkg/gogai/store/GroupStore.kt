package com.mtkg.gogai.store

import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.Group
import com.mtkg.gogai.model.RefreshResult
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.ApiException
import com.mtkg.gogai.repository.GroupRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/// グループ一覧・シークレット表示・展開状態を保持する Store（iOS GroupStore の移植）
class GroupStore(private val cache: AppCache) {
    private val _groups = MutableStateFlow<List<Group>>(cache.loadGroups())
    val groups: StateFlow<List<Group>> = _groups.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()

    /// シークレットグループの表示フラグ（保存されない、バックグラウンド復帰でリセット）
    private val _showSecretGroups = MutableStateFlow(false)
    val showSecretGroups: StateFlow<Boolean> = _showSecretGroups.asStateFlow()

    /// 折りたたまれているグループIDのセット（未含有 = 展開済み）
    private val _collapsedGroupIds = MutableStateFlow<Set<Int>>(emptySet())

    private var client: ApiClient? = null

    fun configure(client: ApiClient) {
        this.client = client
    }

    val visibleGroups: List<Group>
        get() = if (_showSecretGroups.value) _groups.value else _groups.value.filterNot { it.isSecret }

    fun setShowSecretGroups(value: Boolean) {
        _showSecretGroups.value = value
    }

    /// バックグラウンド復帰時にシークレット表示状態をリセットする。
    /// 呼び出しは Phase 3 の UI 側（ProcessLifecycle 相当）で行う。
    fun resetSecretVisibility() {
        _showSecretGroups.value = false
    }

    /// 非表示にすべきシークレットグループ所属フィードの ID 集合。
    /// シークレット表示中（showSecretGroups=true）は隠すものがないため空集合。
    fun secretFeedIds(feeds: List<Feed>): Set<Int> {
        if (_showSecretGroups.value) return emptySet()
        val secretGroupIds = _groups.value.filter { it.isSecret }.map { it.id }.toSet()
        if (secretGroupIds.isEmpty()) return emptySet()
        return feeds.mapNotNull { feed ->
            val gid = feed.group_id
            if (gid != null && secretGroupIds.contains(gid)) feed.id else null
        }.toSet()
    }

    fun isExpanded(id: Int): Boolean = !_collapsedGroupIds.value.contains(id)

    fun toggleExpanded(id: Int) {
        _collapsedGroupIds.value = if (_collapsedGroupIds.value.contains(id)) {
            _collapsedGroupIds.value - id
        } else {
            _collapsedGroupIds.value + id
        }
    }

    suspend fun fetchGroups() {
        val client = this.client ?: return
        _isLoading.value = true
        try {
            val fetched = GroupRepository(client).fetchAll()
            _groups.value = fetched
            cache.saveGroups(fetched)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.value = e
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun createGroup(name: String) {
        val client = this.client ?: return
        val newGroup = GroupRepository(client).create(name)
        _groups.value = _groups.value + newGroup
    }

    suspend fun updateGroup(id: Int, name: String, isSecret: Int? = null) {
        val client = this.client ?: return
        val updated = GroupRepository(client).update(id, name, isSecret)
        val idx = _groups.value.indexOfFirst { it.id == id }
        if (idx >= 0) {
            _groups.value = _groups.value.toMutableList().also { it[idx] = updated }
        }
    }

    suspend fun deleteGroup(id: Int) {
        val client = this.client ?: return
        GroupRepository(client).delete(id)
        _groups.value = _groups.value.filterNot { it.id == id }
        _collapsedGroupIds.value = _collapsedGroupIds.value - id
    }

    suspend fun refreshGroup(id: Int): RefreshResult {
        val client = this.client ?: throw ApiException.InvalidUrl()
        return GroupRepository(client).refresh(id)
    }

    suspend fun reorderGroups(from: Int, to: Int) {
        val client = this.client ?: return
        _groups.value = reorderAndPersist(_groups.value, from, to, { it.id }) { ids ->
            GroupRepository(client).reorder(ids)
        }
    }
}
