package com.mtkg.gogai.ui.stocks

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.ui.common.FormSheetDialog

/// ストック追加フォーム（iOS AddStockView の移植）。
/// カテゴリはストック元の入力に自動追従し、ユーザーが手動編集したら追従を止める。
@Composable
fun AddStockSheet(
    stockStore: StockStore,
    onDismiss: () -> Unit,
) {
    var urlText by remember { mutableStateOf("") }
    var titleText by remember { mutableStateOf("") }
    var sourceText by remember { mutableStateOf("") }
    var categoryText by remember { mutableStateOf("") }
    var categoryEditedManually by remember { mutableStateOf(false) }

    FormSheetDialog(
        title = stringResource(R.string.stock_add_title),
        confirmLabel = stringResource(R.string.add),
        confirmEnabled = urlText.trim().isNotEmpty(),
        onDismiss = onDismiss,
        onSubmit = {
            val url = urlText.trim()
            val title = titleText.trim()
            val source = sourceText.trim()
            val category = categoryText.trim()
            stockStore.createStock(
                url = url,
                title = title.ifEmpty { null },
                source = source.ifEmpty { null },
                category = category.ifEmpty { null },
            )
        },
    ) {
        Column {
            Text(
                text = "URL",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = urlText,
                onValueChange = { urlText = it },
                placeholder = { Text(stringResource(R.string.stock_add_url_placeholder)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Column {
            Text(
                text = stringResource(R.string.stock_add_title_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = titleText,
                onValueChange = { titleText = it },
                placeholder = { Text(stringResource(R.string.stock_add_title_placeholder)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Column {
            Text(
                text = stringResource(R.string.stock_add_source_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = sourceText,
                onValueChange = { newValue ->
                    sourceText = newValue
                    // カテゴリを未編集ならストック元の入力に追従させる
                    if (!categoryEditedManually) categoryText = newValue
                },
                placeholder = { Text(stringResource(R.string.stock_add_source_placeholder)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Column {
            Text(
                text = stringResource(R.string.stock_add_category_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = categoryText,
                onValueChange = { newValue ->
                    categoryText = newValue
                    categoryEditedManually = true
                },
                placeholder = { Text(stringResource(R.string.stock_add_category_placeholder)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
