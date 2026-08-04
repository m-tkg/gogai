package com.mtkg.gogai.ui.stocks

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.StockCategory
import com.mtkg.gogai.store.StockStore
import kotlinx.coroutines.launch

/// ストックのカテゴリ(フォルダ)一覧（iOS StockCategoryListView の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StockCategoryListScreen(
    stockStore: StockStore,
    onCategorySelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onClose: (() -> Unit)? = null,
    aiAvailable: Boolean = false,
) {
    val categories by stockStore.categories.collectAsState()
    val stocks by stockStore.stocks.collectAsState()
    val pending by stockStore.pendingSummaryStockIds.collectAsState()
    val current by stockStore.currentlySummarizingStockId.collectAsState()
    val summaryErrors by stockStore.summaryErrors.collectAsState()
    val isPausedByUser by stockStore.isSummaryQueuePausedByUser.collectAsState()
    val isLoading by stockStore.isLoading.collectAsState()

    var hasAppeared by rememberSaveable { mutableStateOf(false) }
    var isEditing by remember { mutableStateOf(false) }
    var showAddStock by remember { mutableStateOf(false) }
    var isQueueExpanded by rememberSaveable { mutableStateOf(true) }
    var reorderError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    // iOS: .task { guard !hasAppeared ... } 相当。StockListScreen から戻ってきた際の
    // 再フェッチ(一覧の一瞬のリセット)を防ぐ。手動更新は PullToRefresh 側で常に行う。
    LaunchedEffect(Unit) {
        if (!hasAppeared) {
            hasAppeared = true
            stockStore.fetchAll()
        }
    }

    fun titleFor(stockId: Int) = stocks.firstOrNull { it.id == stockId }?.title ?: "記事"

    val summaryQueueItems = buildList {
        current?.let { add(SummaryQueueItem(it, titleFor(it), isGenerating = true)) }
        pending.forEach { add(SummaryQueueItem(it, titleFor(it), isGenerating = false)) }
    }
    val unsummarizedIds = stocks.filter { it.summary == null }.map { it.id }

    fun categoryHasSummaryError(category: StockCategory) =
        stocks.any { it.category_id == category.id && summaryErrors.containsKey(it.id) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.stock_title)) },
                navigationIcon = {
                    onClose?.let {
                        IconButton(onClick = it) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.cancel))
                        }
                    }
                },
                actions = {
                    TextButton(onClick = { isEditing = !isEditing }) {
                        Text(if (isEditing) stringResource(R.string.sidebar_done) else stringResource(R.string.sidebar_edit))
                    }
                    IconButton(onClick = { showAddStock = true }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.sidebar_add_content_description))
                    }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { scope.launch { stockStore.fetchAll() } },
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            if (categories.isEmpty() && !isLoading) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.stock_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (aiAvailable && unsummarizedIds.isNotEmpty()) {
                        item(key = "summarize-all") {
                            ListItem(
                                headlineContent = { Text(stringResource(R.string.stock_summarize_all_unsummarized)) },
                                leadingContent = { Icon(Icons.Filled.AutoAwesome, contentDescription = null) },
                                modifier = Modifier.clickable {
                                    unsummarizedIds.forEach { stockStore.requestSummary(it) }
                                },
                            )
                        }
                    }
                    if (summaryQueueItems.isNotEmpty()) {
                        item(key = "summary-queue") {
                            SummaryQueueSection(
                                items = summaryQueueItems,
                                expanded = isQueueExpanded,
                                onExpandedChange = { isQueueExpanded = it },
                                isPausedByUser = isPausedByUser,
                                onCancel = { stockStore.cancelSummary(it) },
                                onTogglePause = {
                                    if (isPausedByUser) stockStore.resumeSummaryQueue() else stockStore.pauseSummaryQueue()
                                },
                            )
                        }
                    }
                    itemsIndexed(categories, key = { _, c -> c.id }) { index, category ->
                        CategoryRow(
                            category = category,
                            hasSummaryError = categoryHasSummaryError(category),
                            isEditing = isEditing,
                            canMoveUp = index > 0,
                            canMoveDown = index < categories.size - 1,
                            onClick = { onCategorySelected(category.id) },
                            onMoveUp = {
                                scope.launch {
                                    try {
                                        stockStore.reorderCategories(index, index - 1)
                                    } catch (e: Exception) {
                                        reorderError = e.message ?: e.toString()
                                    }
                                }
                            },
                            onMoveDown = {
                                scope.launch {
                                    try {
                                        stockStore.reorderCategories(index, index + 2)
                                    } catch (e: Exception) {
                                        reorderError = e.message ?: e.toString()
                                    }
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    if (showAddStock) {
        AddStockSheet(stockStore = stockStore, onDismiss = { showAddStock = false })
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

private data class SummaryQueueItem(val id: Int, val title: String, val isGenerating: Boolean)

@Composable
private fun CategoryRow(
    category: StockCategory,
    hasSummaryError: Boolean,
    isEditing: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onClick: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Folder, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(category.name, modifier = Modifier.padding(start = 12.dp).weight(1f))
        if (hasSummaryError) {
            Icon(Icons.Filled.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.padding(end = 8.dp))
        }
        if (isEditing) {
            IconButton(onClick = onMoveUp, enabled = canMoveUp) { Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null) }
            IconButton(onClick = onMoveDown, enabled = canMoveDown) { Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null) }
        }
        Text("${category.stock_count}", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/// 要約キュー(生成中 + 順番待ち)の一覧を展開/折りたたみで表示するセクション（iOS SummaryQueueSection の移植）。
@Composable
private fun SummaryQueueSection(
    items: List<SummaryQueueItem>,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    isPausedByUser: Boolean,
    onCancel: (Int) -> Unit,
    onTogglePause: () -> Unit,
) {
    Surface {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onExpandedChange(!expanded) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.stock_summary_queue_title, items.size))
                if (isPausedByUser) {
                    Text(
                        text = stringResource(R.string.stock_summary_queue_paused),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
                androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
                IconButton(onClick = onTogglePause) {
                    Icon(if (isPausedByUser) Icons.Filled.PlayArrow else Icons.Filled.Pause, contentDescription = null)
                }
                Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
            }
            if (expanded) {
                items.forEach { item ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (item.isGenerating) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Filled.HourglassEmpty, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                        }
                        Text(
                            text = item.title,
                            maxLines = 1,
                            modifier = Modifier.padding(start = 8.dp).weight(1f),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Text(
                            text = if (item.isGenerating) stringResource(R.string.stock_status_generating) else stringResource(R.string.stock_status_queued),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        IconButton(onClick = { onCancel(item.id) }) {
                            Icon(Icons.Filled.Cancel, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
