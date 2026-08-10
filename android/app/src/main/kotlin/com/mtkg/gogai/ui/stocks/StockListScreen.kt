package com.mtkg.gogai.ui.stocks

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.ui.ai.TranslatedPageScreen
import com.mtkg.gogai.ui.common.SwipeAction
import com.mtkg.gogai.ui.common.SwipeActionRow
import com.mtkg.gogai.ui.common.openInCustomTabs
import kotlinx.coroutines.launch

/// カテゴリ内のストック一覧（iOS StockListView の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StockListScreen(
    categoryId: Int,
    categoryName: String,
    stockStore: StockStore,
    onStockSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
    aiAvailable: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val allStocks by stockStore.stocks.collectAsState()
    val sortAscending by stockStore.sortAscending.collectAsState()
    val pending by stockStore.pendingSummaryStockIds.collectAsState()
    val current by stockStore.currentlySummarizingStockId.collectAsState()
    val summaryErrors by stockStore.summaryErrors.collectAsState()
    val isLoading by stockStore.isLoading.collectAsState()

    // stocksIn() は sortAscending に連動するため、購読済みの sortAscending/allStocks を
    // 経由してここで再計算されるようにする。
    val stocks = remember(allStocks, sortAscending, categoryId) { stockStore.stocksIn(categoryId) }

    var stockPendingDelete by remember { mutableStateOf<Stock?>(null) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    var summaryErrorStock by remember { mutableStateOf<Stock?>(null) }
    var editingStock by remember { mutableStateOf<Stock?>(null) }
    var previousSummaryErrors by remember { mutableStateOf<Map<Int, String>>(emptyMap()) }
    // 翻訳オーバーレイ（iOS の sheet(item:) 相当）。NavHost に route を足さず状態切替で表示する。
    var translatingStock by remember { mutableStateOf<Stock?>(null) }

    // iOS: .onChange(of: summaryError) { old, new in if old == nil, new != nil { ... } } 相当。
    // nil→non-nil への遷移時のみ自動でアラート表示する（スクロール中に何度も出ないようにするため）。
    LaunchedEffect(summaryErrors) {
        val newlyFailedId = summaryErrors.keys.firstOrNull { id ->
            id !in previousSummaryErrors && stocks.any { it.id == id }
        }
        if (newlyFailedId != null) {
            summaryErrorStock = stocks.firstOrNull { it.id == newlyFailedId }
        }
        previousSummaryErrors = summaryErrors
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(categoryName) },
                actions = {
                    IconButton(onClick = { stockStore.setSortAscending(!sortAscending) }) {
                        Icon(
                            imageVector = if (sortAscending) Icons.Filled.ArrowUpward else Icons.Filled.ArrowDownward,
                            contentDescription = stringResource(R.string.stock_sort_content_description),
                        )
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
            if (stocks.isEmpty() && !isLoading) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.stock_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(stocks, key = { it.id }) { stock ->
                        val isGeneratingSummary = current == stock.id || pending.contains(stock.id)
                        val isQueued = pending.contains(stock.id)
                        val summaryError = summaryErrors[stock.id]

                        SwipeActionRow(
                            trailing = listOf(
                                SwipeAction(
                                    icon = Icons.Filled.Delete,
                                    label = stringResource(R.string.feed_delete),
                                    color = MaterialTheme.colorScheme.error,
                                    onClick = { stockPendingDelete = stock },
                                ),
                            ),
                            allowsLeadingFullSwipe = false,
                        ) {
                            StockRow(
                                stock = stock,
                                isGeneratingSummary = isGeneratingSummary,
                                isQueued = isQueued,
                                summaryError = summaryError,
                                canShowTranslation = stock.has_translation || aiAvailable,
                                canGenerateSummary = aiAvailable,
                                onClick = { onStockSelected(stock.id) },
                                onSummaryErrorTap = { summaryErrorStock = stock },
                                onOpenBrowser = { openInCustomTabs(context, stock.url) },
                                onTranslate = { translatingStock = stock },
                                onGenerateSummary = { stockStore.requestSummary(stock.id) },
                                onEdit = { editingStock = stock },
                                onDeleteRequest = { stockPendingDelete = stock },
                            )
                        }
                    }
                }
            }
        }
    }

    stockPendingDelete?.let { stock ->
        AlertDialog(
            onDismissRequest = { stockPendingDelete = null },
            title = { Text(stringResource(R.string.stock_delete_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    stockPendingDelete = null
                    scope.launch {
                        try {
                            stockStore.deleteStock(stock.id)
                        } catch (e: Exception) {
                            deleteError = e.message ?: e.toString()
                        }
                    }
                }) { Text(stringResource(R.string.feed_delete)) }
            },
            dismissButton = {
                TextButton(onClick = { stockPendingDelete = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    deleteError?.let { message ->
        AlertDialog(
            onDismissRequest = { deleteError = null },
            title = { Text(stringResource(R.string.stock_delete_failed_title)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { deleteError = null }) { Text(stringResource(R.string.ok)) } },
        )
    }

    summaryErrorStock?.let { stock ->
        AlertDialog(
            onDismissRequest = { summaryErrorStock = null },
            title = { Text(stringResource(R.string.stock_summary_failed_title)) },
            text = { Text(summaryErrors[stock.id] ?: "") },
            confirmButton = {
                TextButton(onClick = {
                    stockStore.clearSummaryError(stock.id)
                    summaryErrorStock = null
                }) { Text(stringResource(R.string.ok)) }
            },
        )
    }

    editingStock?.let { stock ->
        EditStockSheet(stock = stock, stockStore = stockStore, onDismiss = { editingStock = null })
    }

    translatingStock?.let { stock ->
        TranslatedPageScreen(stock = stock, stockStore = stockStore, onClose = { translatingStock = null })
    }
}
