package com.mtkg.gogai.ui.sidebar

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.PostAdd
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.Group
import com.mtkg.gogai.store.ArticleStore
import com.mtkg.gogai.store.FeedStore
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.store.SettingsStore
import com.mtkg.gogai.ui.common.FilterFooter
import com.mtkg.gogai.ui.common.UnreadCountBadge
import com.mtkg.gogai.ui.theme.SecretOrange
import kotlinx.coroutines.launch

/// フィードページ（iOS SidebarView の移植）。「すべての記事」+ グループセクション + 未分類セクション。
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SidebarScreen(
    groupStore: GroupStore,
    feedStore: FeedStore,
    articleStore: ArticleStore,
    settingsStore: SettingsStore,
    onSelectAll: () -> Unit,
    onSelectFeed: (Int) -> Unit,
    onSelectGroup: (Int) -> Unit,
    onStockTap: () -> Unit,
    onSettingsTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val groups by groupStore.groups.collectAsState()
    val showSecretGroups by groupStore.showSecretGroups.collectAsState()
    val isGroupLoading by groupStore.isLoading.collectAsState()

    val feeds by feedStore.feeds.collectAsState()
    val isFeedLoading by feedStore.isLoading.collectAsState()
    val isFeedRefreshing by feedStore.isRefreshing.collectAsState()

    // articleStore の各種派生関数（badgeCount 等）は StateFlow ではなく現在値のスナップショットを
    // 読むため、依存する StateFlow をここで collectAsState しておくことで再結合をトリガーする。
    @Suppress("UNUSED_VARIABLE") val feedCounts by articleStore.feedCounts.collectAsState()
    @Suppress("UNUSED_VARIABLE") val allArticles by articleStore.allArticles.collectAsState()
    @Suppress("UNUSED_VARIABLE") val articles by articleStore.articles.collectAsState()
    val unreadOnly by articleStore.unreadOnly.collectAsState()
    val isArticleLoading by articleStore.isLoading.collectAsState()

    val isSettingsLoading by settingsStore.isLoading.collectAsState()

    val visibleGroups = if (showSecretGroups) groups else groups.filterNot { it.isSecret }
    val secretFeedIds = groupStore.secretFeedIds(feeds)
    val totalBadgeCount = articleStore.badgeCountExcluding(secretFeedIds)
    val ungroupedFeeds = feeds.filter { it.group_id == null && articleStore.hasVisibleArticle(it.id) }

    var isEditing by remember { mutableStateOf(false) }
    var showAddFeed by remember { mutableStateOf(false) }
    var showAddGroup by remember { mutableStateOf(false) }
    var addMenuExpanded by remember { mutableStateOf(false) }
    var refreshError by remember { mutableStateOf<String?>(null) }
    var reorderError by remember { mutableStateOf<String?>(null) }
    var editingFeed by remember { mutableStateOf<Feed?>(null) }

    val scope = rememberCoroutineScope()
    val isNetworkActive = isFeedLoading || isFeedRefreshing || isGroupLoading || isArticleLoading || isSettingsLoading

    LaunchedEffect(showSecretGroups) {
        if (showSecretGroups) articleStore.refreshCounts()
    }

    fun reorderGroup(group: Group, direction: Int) {
        val (from, to) = adjacentSwapIndices(groups, visibleGroups, group, direction, Group::id) ?: return
        scope.launch {
            try {
                groupStore.reorderGroups(from, to)
            } catch (e: Exception) {
                reorderError = e.message ?: e.toString()
            }
        }
    }

    fun reorderFeed(feed: Feed, visibleFeedsInSection: List<Feed>, groupId: Int?, direction: Int) {
        val allInSection = feedStore.feeds(groupId)
        val (from, to) = adjacentSwapIndices(allInSection, visibleFeedsInSection, feed, direction, Feed::id) ?: return
        scope.launch {
            try {
                feedStore.reorderFeeds(from, to, groupId)
            } catch (e: Exception) {
                reorderError = e.message ?: e.toString()
            }
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.sidebar_title)) },
                navigationIcon = {
                    Box(contentAlignment = Alignment.Center) {
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .combinedClickable(
                                    onClick = onSettingsTap,
                                    onLongClick = { groupStore.setShowSecretGroups(!showSecretGroups) },
                                ),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Settings,
                                contentDescription = if (showSecretGroups) {
                                    stringResource(R.string.sidebar_settings_secret_content_description)
                                } else {
                                    stringResource(R.string.sidebar_settings_content_description)
                                },
                                tint = if (showSecretGroups) SecretOrange else MaterialTheme.colorScheme.onSurface,
                            )
                        }
                        if (isNetworkActive) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        }
                    }
                },
                actions = {
                    TextButton(onClick = { isEditing = !isEditing }) {
                        Text(if (isEditing) stringResource(R.string.sidebar_done) else stringResource(R.string.sidebar_edit))
                    }
                    IconButton(
                        onClick = {
                            scope.launch {
                                try {
                                    feedStore.refreshAll()
                                    feedStore.fetchFeeds()
                                } catch (e: Exception) {
                                    refreshError = e.message ?: e.toString()
                                }
                            }
                        },
                        enabled = !isFeedRefreshing,
                    ) {
                        if (isFeedRefreshing) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.sidebar_refresh_content_description))
                        }
                    }
                    Box {
                        IconButton(onClick = { addMenuExpanded = true }) {
                            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.sidebar_add_content_description))
                        }
                        DropdownMenu(expanded = addMenuExpanded, onDismissRequest = { addMenuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.sidebar_add_feed)) },
                                leadingIcon = { Icon(Icons.Filled.PostAdd, contentDescription = null) },
                                onClick = { addMenuExpanded = false; showAddFeed = true },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.sidebar_add_group)) },
                                leadingIcon = { Icon(Icons.Filled.CreateNewFolder, contentDescription = null) },
                                onClick = { addMenuExpanded = false; showAddGroup = true },
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            FilterFooter(
                unreadOnly = unreadOnly,
                onUnreadOnlyChange = { articleStore.setUnreadOnly(it) },
                onStockTap = onStockTap,
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding).fillMaxSize()) {
            item(key = "all") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .combinedClickable(onClick = onSelectAll)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Article,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(end = 8.dp),
                    )
                    Text(stringResource(R.string.sidebar_all_articles), modifier = Modifier.weight(1f))
                    UnreadCountBadge(totalBadgeCount)
                }
            }

            visibleGroups.forEachIndexed { index, group ->
                val feedsInGroup = feedStore.feeds(group.id).filter { articleStore.hasVisibleArticle(it.id) }
                if (feedsInGroup.isNotEmpty()) {
                    item(key = "group-${group.id}") {
                        GroupRow(
                            group = group,
                            isExpanded = groupStore.isExpanded(group.id),
                            badgeCount = articleStore.badgeCountForGroup(feedStore.feeds(group.id).map { it.id }),
                            showSecretGroups = showSecretGroups,
                            isEditing = isEditing,
                            canMoveUp = index > 0,
                            canMoveDown = index < visibleGroups.size - 1,
                            onToggleExpanded = { groupStore.toggleExpanded(group.id) },
                            onSelect = { onSelectGroup(group.id) },
                            onToggleSecret = {
                                scope.launch { runCatching { groupStore.updateGroup(group.id, group.name, if (group.isSecret) 0 else 1) } }
                            },
                            onRename = { newName ->
                                scope.launch { runCatching { groupStore.updateGroup(group.id, newName) } }
                            },
                            onDelete = {
                                scope.launch { runCatching { groupStore.deleteGroup(group.id) } }
                            },
                            onMoveUp = { reorderGroup(group, -1) },
                            onMoveDown = { reorderGroup(group, 1) },
                        )
                    }
                    if (groupStore.isExpanded(group.id)) {
                        itemsIndexedKeyed(feedsInGroup, keyPrefix = "feed") { feedIndex, feed ->
                            FeedRow(
                                feed = feed,
                                badgeCount = articleStore.badgeCount(feed.id),
                                isEditing = isEditing,
                                canMoveUp = feedIndex > 0,
                                canMoveDown = feedIndex < feedsInGroup.size - 1,
                                onSelect = { onSelectFeed(feed.id) },
                                onEdit = { editingFeed = feed },
                                onDelete = {
                                    scope.launch { runCatching { feedStore.deleteFeed(feed.id) } }
                                },
                                onMoveUp = { reorderFeed(feed, feedsInGroup, group.id, -1) },
                                onMoveDown = { reorderFeed(feed, feedsInGroup, group.id, 1) },
                            )
                        }
                    }
                }
            }

            if (ungroupedFeeds.isNotEmpty()) {
                item(key = "ungrouped-header") {
                    Text(
                        text = stringResource(R.string.sidebar_section_ungrouped),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                itemsIndexedKeyed(ungroupedFeeds, keyPrefix = "ungrouped") { feedIndex, feed ->
                    FeedRow(
                        feed = feed,
                        badgeCount = articleStore.badgeCount(feed.id),
                        isEditing = isEditing,
                        canMoveUp = feedIndex > 0,
                        canMoveDown = feedIndex < ungroupedFeeds.size - 1,
                        onSelect = { onSelectFeed(feed.id) },
                        onEdit = { editingFeed = feed },
                        onDelete = {
                            scope.launch { runCatching { feedStore.deleteFeed(feed.id) } }
                        },
                        onMoveUp = { reorderFeed(feed, ungroupedFeeds, null, -1) },
                        onMoveDown = { reorderFeed(feed, ungroupedFeeds, null, 1) },
                    )
                }
            }
        }
    }

    if (showAddFeed) {
        AddFeedSheet(feedStore = feedStore, groupStore = groupStore, onDismiss = { showAddFeed = false })
    }
    if (showAddGroup) {
        AddGroupSheet(groupStore = groupStore, onDismiss = { showAddGroup = false })
    }
    editingFeed?.let { feed ->
        EditFeedSheet(feed = feed, feedStore = feedStore, groupStore = groupStore, onDismiss = { editingFeed = null })
    }

    refreshError?.let { message ->
        AlertDialog(
            onDismissRequest = { refreshError = null },
            title = { Text(stringResource(R.string.error_title)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { refreshError = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
    reorderError?.let { message ->
        AlertDialog(
            onDismissRequest = { reorderError = null },
            title = { Text(stringResource(R.string.reorder_error_title)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { reorderError = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/// LazyListScope.items のインデックス付きラッパー（key を安定させるための小ヘルパー）
private fun LazyListScope.itemsIndexedKeyed(
    items: List<Feed>,
    keyPrefix: String,
    itemContent: @Composable (Int, Feed) -> Unit,
) {
    itemsIndexed(items, key = { _, feed -> "$keyPrefix-${feed.id}" }) { index, feed ->
        itemContent(index, feed)
    }
}

/// 「表示中リスト」上で隣接する要素とスワップするための、「全件リスト」上の実インデックスを計算する。
/// visible は all の部分集合（フィルタ済み）である前提。ReorderHelper の move セマンティクス
/// （destination は移動前配列に対するインデックス）に合わせて to を計算する。
private fun <T> adjacentSwapIndices(all: List<T>, visible: List<T>, item: T, direction: Int, idOf: (T) -> Int): Pair<Int, Int>? {
    val visibleIndex = visible.indexOfFirst { idOf(it) == idOf(item) }
    if (visibleIndex < 0) return null
    val neighbor = visible.getOrNull(visibleIndex + direction) ?: return null
    val fromReal = all.indexOfFirst { idOf(it) == idOf(item) }
    val neighborReal = all.indexOfFirst { idOf(it) == idOf(neighbor) }
    if (fromReal < 0 || neighborReal < 0) return null
    val to = if (direction < 0) neighborReal else neighborReal + 1
    return fromReal to to
}
