package com.mtkg.gogai.ui.stocks

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.ui.common.FormSheetDialog

/// ストック編集フォーム（iOS EditStockView の移植）。編集できるのはタイトルとカテゴリのみ
/// （ストック元は作成後不変のため読み取り専用表示）。
@Composable
fun EditStockSheet(
    stock: Stock,
    stockStore: StockStore,
    onDismiss: () -> Unit,
) {
    var titleText by remember { mutableStateOf(stock.title.orEmpty()) }
    var categoryText by remember { mutableStateOf(stock.category_name) }
    var categoryMenuExpanded by remember { mutableStateOf(false) }
    val categories by stockStore.categories.collectAsState()

    FormSheetDialog(
        title = stringResource(R.string.stock_edit_title),
        confirmLabel = stringResource(R.string.save),
        confirmEnabled = categoryText.trim().isNotEmpty(),
        onDismiss = onDismiss,
        onSubmit = {
            stockStore.updateStock(id = stock.id, title = titleText.trim(), category = categoryText.trim())
        },
    ) {
        Column {
            Text(
                text = stringResource(R.string.edit_feed_title_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = titleText,
                onValueChange = { titleText = it },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Column {
            Row {
                Text(
                    text = stringResource(R.string.stock_add_category_section),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (categories.isNotEmpty()) {
                    androidx.compose.foundation.layout.Box {
                        TextButton(onClick = { categoryMenuExpanded = true }) {
                            Text(stringResource(R.string.stock_edit_pick_existing_category))
                        }
                        DropdownMenu(expanded = categoryMenuExpanded, onDismissRequest = { categoryMenuExpanded = false }) {
                            categories.forEach { category ->
                                DropdownMenuItem(
                                    text = { Text(category.name) },
                                    onClick = { categoryText = category.name; categoryMenuExpanded = false },
                                )
                            }
                        }
                    }
                }
            }
            OutlinedTextField(
                value = categoryText,
                onValueChange = { categoryText = it },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Column {
            Text(
                text = stringResource(R.string.stock_edit_source_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(stock.source, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
