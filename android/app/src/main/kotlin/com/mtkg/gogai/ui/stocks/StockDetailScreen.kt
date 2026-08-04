package com.mtkg.gogai.ui.stocks

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PostAdd
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.ai.StockSummary
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.ui.ai.TranslatedPageScreen
import com.mtkg.gogai.ui.common.shareUrl
import com.mtkg.gogai.ui.common.openInCustomTabs
import com.mtkg.gogai.util.HorizontalSwipeDirection
import com.mtkg.gogai.util.displayDate
import com.mtkg.gogai.util.matchHorizontalSwipe
import kotlinx.coroutines.launch

/// ストック詳細ページ（iOS StockDetailView の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StockDetailScreen(
    stockId: Int,
    stockStore: StockStore,
    modifier: Modifier = Modifier,
    onDeleted: (() -> Unit)? = null,
    aiAvailable: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val stocks by stockStore.stocks.collectAsState()
    val pending by stockStore.pendingSummaryStockIds.collectAsState()
    val current by stockStore.currentlySummarizingStockId.collectAsState()
    val summaryErrors by stockStore.summaryErrors.collectAsState()
    val progressLogs by stockStore.summaryProgressLogs.collectAsState()

    val stock = stocks.firstOrNull { it.id == stockId } ?: run {
        Scaffold(modifier = modifier) { padding -> Column(modifier = Modifier.padding(padding).fillMaxSize()) {} }
        return
    }

    val isGeneratingSummary = current == stock.id || pending.contains(stock.id)
    val isQueued = pending.contains(stock.id)
    val summaryError = summaryErrors[stock.id]
    val logs = (progressLogs[stock.id] ?: emptyList()).takeLast(12)
    val canShowTranslation = stock.has_translation || aiAvailable

    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showRegenerateConfirm by remember { mutableStateOf(false) }
    var editingStock by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    // 翻訳オーバーレイ（iOS の sheet(item:) 相当）。NavHost に route を足さず状態切替で表示する。
    var showTranslation by remember { mutableStateOf(false) }

    var dx by remember { mutableFloatStateOf(0f) }
    var dy by remember { mutableFloatStateOf(0f) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(title = { Text(stringResource(R.string.stock_detail_title)) })
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .pointerInput(stockId) {
                    detectDragGestures(
                        onDragStart = { dx = 0f; dy = 0f },
                        onDragEnd = {
                            if (matchHorizontalSwipe(dx, dy) == HorizontalSwipeDirection.Left) {
                                openInCustomTabs(context, stock.url)
                            }
                        },
                        onDrag = { change, amount -> change.consume(); dx += amount.x; dy += amount.y },
                    )
                },
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
            ) {
                Text(text = stock.title ?: stock.url, style = MaterialTheme.typography.headlineSmall)

                Row(modifier = Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    LabeledIcon(icon = Icons.Filled.Folder, text = stock.source)
                    LabeledIcon(icon = Icons.Filled.Schedule, text = stock.stocked_at.displayDate())
                }

                HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

                StockSummaryContent(
                    summary = stock.summary,
                    isGeneratingSummary = isGeneratingSummary,
                    isQueued = isQueued,
                    summaryError = summaryError,
                    progressLogs = logs,
                )
            }

            HorizontalDivider()
            Surface {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    FooterButton(icon = Icons.Filled.Share, label = stringResource(R.string.article_detail_share_content_description)) {
                        shareUrl(context, stock.url)
                    }
                    if (aiAvailable) {
                        FooterButton(
                            icon = Icons.Filled.AutoAwesome,
                            label = stringResource(R.string.stock_summary_button_label),
                            isLoading = isGeneratingSummary,
                            isDisabled = isGeneratingSummary,
                        ) {
                            if (stock.summary != null) {
                                showRegenerateConfirm = true
                            } else {
                                stockStore.requestSummary(stock.id)
                            }
                        }
                    }
                    if (canShowTranslation) {
                        FooterButton(icon = Icons.Filled.Translate, label = stringResource(R.string.stock_translate)) {
                            showTranslation = true
                        }
                    }
                    FooterButton(icon = Icons.AutoMirrored.Filled.OpenInNew, label = stringResource(R.string.stock_view)) {
                        openInCustomTabs(context, stock.url)
                    }
                    FooterButton(icon = Icons.Filled.Edit, label = stringResource(R.string.feed_edit)) {
                        editingStock = true
                    }
                    FooterButton(icon = Icons.Filled.Delete, label = stringResource(R.string.feed_delete), isDestructive = true) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
    }

    if (showRegenerateConfirm) {
        AlertDialog(
            onDismissRequest = { showRegenerateConfirm = false },
            title = { Text(stringResource(R.string.stock_regenerate_summary_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    showRegenerateConfirm = false
                    stockStore.requestSummary(stock.id, force = true)
                }) { Text(stringResource(R.string.stock_regenerate_summary_confirm_action)) }
            },
            dismissButton = {
                TextButton(onClick = { showRegenerateConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.stock_delete_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    scope.launch {
                        try {
                            stockStore.deleteStock(stock.id)
                            onDeleted?.invoke()
                        } catch (e: Exception) {
                            deleteError = e.message ?: e.toString()
                        }
                    }
                }) { Text(stringResource(R.string.feed_delete)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text(stringResource(R.string.cancel)) }
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

    if (editingStock) {
        EditStockSheet(stock = stock, stockStore = stockStore, onDismiss = { editingStock = false })
    }

    if (showTranslation) {
        TranslatedPageScreen(stock = stock, stockStore = stockStore, onClose = { showTranslation = false })
    }
}

@Composable
private fun LabeledIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp))
    }
}

@Composable
private fun FooterButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    isDestructive: Boolean = false,
    isLoading: Boolean = false,
    isDisabled: Boolean = false,
    onClick: () -> Unit,
) {
    val color = if (isDestructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    TextButton(onClick = onClick, enabled = !isDisabled) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            } else {
                Icon(icon, contentDescription = null, tint = color)
            }
            Text(label, style = MaterialTheme.typography.labelSmall, color = color)
        }
    }
}

@Composable
private fun StockSummaryContent(
    summary: String?,
    isGeneratingSummary: Boolean,
    isQueued: Boolean,
    summaryError: String?,
    progressLogs: List<String>,
) {
    when {
        summary != null -> StockSummarySections(summary = summary)
        isGeneratingSummary -> {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text(
                        text = if (isQueued) stringResource(R.string.stock_summary_queued_message) else stringResource(R.string.stock_summary_generating_message),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
                if (progressLogs.isNotEmpty()) {
                    Column(modifier = Modifier.padding(top = 12.dp, start = 2.dp)) {
                        progressLogs.forEach { log ->
                            Text(
                                text = "› $log",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
        summaryError != null -> {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Text(
                        text = stringResource(R.string.stock_status_summary_error),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
                Text(
                    text = summaryError,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        else -> {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.PostAdd, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    text = stringResource(R.string.stock_summary_not_yet),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }
    }
}

/// iOS StockSummarySections の移植。ai.StockSummary のパーサで 5 セクションに分けて表示する。
/// パース不能なら生テキストへフォールバックする。
@Composable
private fun StockSummarySections(summary: String) {
    val parsed = remember(summary) { StockSummary.parse(summary) }
    if (parsed == null) {
        Text(summary)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        SummarySection(title = stringResource(R.string.stock_summary_section_topic), body = parsed.topic)
        SummarySection(title = stringResource(R.string.stock_summary_section_purpose), body = parsed.purpose)
        SummarySection(title = stringResource(R.string.stock_summary_section_main_message), body = parsed.mainMessage)
        Column {
            SectionTitle(stringResource(R.string.stock_summary_section_summary))
            parsed.summaryLines.forEach { line -> Text(line) }
        }
        parsed.learningLines?.let { lines ->
            Column {
                SectionTitle(stringResource(R.string.stock_summary_section_learning))
                lines.forEach { line -> Text(line) }
            }
        }
    }
}

@Composable
private fun SummarySection(title: String, body: String) {
    Column {
        SectionTitle(title)
        Text(body)
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        text = "【$title】",
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
    )
}
