package com.mtkg.gogai.ui.articles

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MarkEmailRead
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material.icons.filled.MoveToInbox
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
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
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Article
import com.mtkg.gogai.model.ArticleFilter
import com.mtkg.gogai.model.ArticleSortOrder
import com.mtkg.gogai.store.ArticleStore
import com.mtkg.gogai.store.FeedStore
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.ui.common.FilterFooter
import com.mtkg.gogai.ui.common.SwipeAction
import com.mtkg.gogai.ui.common.SwipeActionRow
import com.mtkg.gogai.ui.common.shareUrl
import com.mtkg.gogai.ui.theme.DislikeIndigo
import com.mtkg.gogai.ui.theme.LikePink
import com.mtkg.gogai.ui.theme.SecretOrange
import kotlinx.coroutines.launch

/// 記事一覧ページ（iOS ArticleListView の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArticleListScreen(
    feedId: Int?,
    groupId: Int?,
    articleStore: ArticleStore,
    feedStore: FeedStore,
    groupStore: GroupStore,
    stockStore: StockStore,
    onArticleSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onStockTap: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val articles by articleStore.articles.collectAsState()
    val isLoading by articleStore.isLoading.collectAsState()
    val filter by articleStore.filter.collectAsState()
    val sortOrder by articleStore.sortOrder.collectAsState()
    val feeds by feedStore.feeds.collectAsState()
    val isFeedRefreshing by feedStore.isRefreshing.collectAsState()
    val groups by groupStore.groups.collectAsState()
    val showSecretGroups by groupStore.showSecretGroups.collectAsState()

    var hasAppeared by rememberSaveable(feedId, groupId) { mutableStateOf(false) }
    var lastFilter by rememberSaveable(feedId, groupId) { mutableStateOf(filter.rawValue) }
    var lastShowSecretGroups by rememberSaveable(feedId, groupId) { mutableStateOf(showSecretGroups) }
    var showMarkAllConfirm by remember { mutableStateOf(false) }
    var sortMenuExpanded by remember { mutableStateOf(false) }

    // iOS ArticleListView.task/onChange 相当: 初回表示は1回だけフェッチし、
    // ArticleDetailScreen から戻る際の再表示では再フェッチしない（既読記事を消さないため）。
    // feedId/groupId が変われば hasAppeared が新しい rememberSaveable キーで初期化されるので
    // 新規表示として扱われ、filter/showSecretGroups は値が実際に変化した場合のみ再フェッチする。
    LaunchedEffect(feedId, groupId, filter, showSecretGroups) {
        when {
            !hasAppeared -> {
                hasAppeared = true
                lastFilter = filter.rawValue
                lastShowSecretGroups = showSecretGroups
                articleStore.fetchArticles(feedId = feedId, groupId = groupId, includeSecret = showSecretGroups)
            }
            filter.rawValue != lastFilter || showSecretGroups != lastShowSecretGroups -> {
                lastFilter = filter.rawValue
                lastShowSecretGroups = showSecretGroups
                articleStore.fetchArticles(feedId = feedId, groupId = groupId, filter = filter, includeSecret = showSecretGroups)
            }
        }
    }

    val secretFeedIds = if (feedId == null && groupId == null) groupStore.secretFeedIds(feeds) else emptySet()
    val displayedArticles = if (secretFeedIds.isEmpty()) articles else articles.filter { it.feed_id !in secretFeedIds }

    val title = when {
        feedId != null -> feeds.firstOrNull { it.id == feedId }?.title ?: stringResource(R.string.article_list_default_title)
        groupId != null -> stringResource(R.string.article_list_default_title)
        else -> stringResource(R.string.sidebar_all_articles)
    }

    fun feedOf(article: Article) = feeds.firstOrNull { it.id == article.feed_id }
    fun groupNameOf(article: Article): String? {
        val gid = feedOf(article)?.group_id ?: return null
        return groups.firstOrNull { it.id == gid }?.name
    }

    fun addToStock(article: Article) {
        val link = article.link ?: return
        val sourceName = groupNameOf(article) ?: context.getString(R.string.unclassified_source)
        scope.launch {
            runCatching { stockStore.createStock(url = link, title = article.title, source = sourceName) }
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                actions = {
                    Box {
                        IconButton(onClick = { sortMenuExpanded = true }) {
                            Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = stringResource(R.string.article_list_sort_content_description))
                        }
                        DropdownMenu(expanded = sortMenuExpanded, onDismissRequest = { sortMenuExpanded = false }) {
                            ArticleSortOrder.entries.forEach { order ->
                                DropdownMenuItem(
                                    text = { Text(order.label) },
                                    leadingIcon = {
                                        if (order == sortOrder) Icon(Icons.Filled.Check, contentDescription = null)
                                    },
                                    onClick = {
                                        sortMenuExpanded = false
                                        articleStore.setSortOrder(order)
                                        scope.launch {
                                            articleStore.fetchArticles(feedId = feedId, groupId = groupId, includeSecret = showSecretGroups)
                                        }
                                    },
                                )
                            }
                        }
                    }
                    IconButton(
                        onClick = { showMarkAllConfirm = true },
                        enabled = displayedArticles.any { !it.isRead },
                    ) {
                        Icon(Icons.Filled.MarkEmailRead, contentDescription = stringResource(R.string.article_list_mark_all_read_content_description))
                    }
                },
            )
        },
        bottomBar = {
            FilterFooter(
                filter = filter,
                onFilterChange = { articleStore.setFilter(it) },
                onStockTap = onStockTap,
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isFeedRefreshing,
            onRefresh = { scope.launch { runCatching { feedStore.refreshAll() } } },
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            when {
                isLoading && displayedArticles.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                displayedArticles.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = stringResource(R.string.article_list_empty),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                else -> {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(displayedArticles, key = { it.id }) { article ->
                            val feed = feedOf(article)
                            SwipeActionRow(
                                leading = SwipeAction(
                                    icon = if (article.isRead) Icons.Filled.MarkEmailUnread else Icons.Filled.MarkEmailRead,
                                    label = if (article.isRead) stringResource(R.string.article_mark_unread) else stringResource(R.string.article_mark_read),
                                    color = if (article.isRead) SecretOrange else MaterialTheme.colorScheme.primary,
                                    onClick = { scope.launch { articleStore.toggleRead(article) } },
                                ),
                                // 先頭のアクションほど端に出るため、浅いスワイプではストックだけが見え、
                                // 深く引くと like が現れる
                                trailing = listOf(
                                    SwipeAction(
                                        icon = Icons.Filled.MoveToInbox,
                                        label = stringResource(R.string.article_add_to_stock),
                                        color = MaterialTheme.colorScheme.primary,
                                        onClick = { addToStock(article) },
                                    ),
                                    SwipeAction(
                                        icon = Icons.Filled.ThumbUp,
                                        label = if (article.isLiked) stringResource(R.string.article_unlike) else stringResource(R.string.article_like),
                                        color = if (article.isLiked) MaterialTheme.colorScheme.outline else LikePink,
                                        onClick = { scope.launch { articleStore.toggleLike(article) } },
                                    ),
                                    SwipeAction(
                                        icon = Icons.Filled.ThumbDown,
                                        label = if (article.isDisliked) stringResource(R.string.article_undislike) else stringResource(R.string.article_dislike),
                                        color = if (article.isDisliked) MaterialTheme.colorScheme.outline else DislikeIndigo,
                                        onClick = { scope.launch { articleStore.toggleDislike(article) } },
                                    ),
                                ),
                                allowsLeadingFullSwipe = true,
                            ) {
                                ArticleRow(
                                    article = article,
                                    faviconUrl = feed?.favicon_url,
                                    groupName = groupNameOf(article),
                                    onClick = {
                                        onArticleSelected(article.id)
                                        if (!article.isRead) {
                                            scope.launch { articleStore.markAsRead(article.id) }
                                        }
                                    },
                                    onLongPressShare = {
                                        article.link?.let { shareUrl(context, it) }
                                    },
                                    onToggleRead = { scope.launch { articleStore.toggleRead(article) } },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showMarkAllConfirm) {
        AlertDialog(
            onDismissRequest = { showMarkAllConfirm = false },
            title = { Text(stringResource(R.string.article_list_mark_all_read_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    showMarkAllConfirm = false
                    scope.launch { articleStore.markAllAsRead() }
                }) {
                    Text(stringResource(R.string.article_list_mark_all_read_confirm_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { showMarkAllConfirm = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
}
