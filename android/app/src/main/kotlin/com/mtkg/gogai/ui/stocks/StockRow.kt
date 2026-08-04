package com.mtkg.gogai.ui.stocks

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.util.displayDate

/// ストック一覧の行（iOS StockRowView の移植）。長押しで元記事/翻訳/要約生成/編集/削除の
/// コンテキストメニューを表示する。削除確認は親（StockListScreen）が保持する。
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun StockRow(
    stock: Stock,
    isGeneratingSummary: Boolean,
    isQueued: Boolean,
    summaryError: String?,
    canShowTranslation: Boolean,
    canGenerateSummary: Boolean,
    onClick: () -> Unit,
    onSummaryErrorTap: () -> Unit,
    onOpenBrowser: () -> Unit,
    onTranslate: () -> Unit,
    onGenerateSummary: () -> Unit,
    onEdit: () -> Unit,
    onDeleteRequest: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showMenu by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = { showMenu = true })
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Text(
            text = stock.title ?: stock.url,
            style = MaterialTheme.typography.bodyLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Row(
            modifier = Modifier.padding(top = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stock.source, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = "  ${stock.stocked_at.displayDate()}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when {
                isGeneratingSummary -> {
                    Row(
                        modifier = Modifier.padding(start = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Filled.AutoAwesome,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = if (isQueued) stringResource(R.string.stock_status_queued) else stringResource(R.string.stock_status_generating),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 2.dp),
                        )
                    }
                }
                summaryError != null -> {
                    Row(
                        modifier = Modifier
                            .padding(start = 8.dp)
                            .combinedClickable(onClick = onSummaryErrorTap),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Error, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error)
                        Text(
                            text = stringResource(R.string.stock_status_summary_error),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(start = 2.dp),
                        )
                    }
                }
                stock.summary == null -> {
                    Row(
                        modifier = Modifier.padding(start = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.HourglassEmpty, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            text = stringResource(R.string.stock_status_summary_pending),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 2.dp),
                        )
                    }
                }
            }
        }
    }

    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.stock_open_original)) },
            leadingIcon = { Icon(Icons.Filled.OpenInBrowser, contentDescription = null) },
            onClick = { showMenu = false; onOpenBrowser() },
        )
        if (canShowTranslation) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.stock_translate)) },
                leadingIcon = { Icon(Icons.Filled.Translate, contentDescription = null) },
                onClick = { showMenu = false; onTranslate() },
            )
        }
        if (stock.summary == null && canGenerateSummary) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.stock_generate_summary)) },
                leadingIcon = {
                    if (isGeneratingSummary) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Filled.AutoAwesome, contentDescription = null)
                    }
                },
                enabled = !isGeneratingSummary,
                onClick = { showMenu = false; onGenerateSummary() },
            )
        }
        DropdownMenuItem(
            text = { Text(stringResource(R.string.feed_edit)) },
            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
            onClick = { showMenu = false; onEdit() },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.feed_delete)) },
            leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
            onClick = { showMenu = false; onDeleteRequest() },
        )
    }
}
