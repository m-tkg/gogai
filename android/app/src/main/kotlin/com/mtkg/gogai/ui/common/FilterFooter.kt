package com.mtkg.gogai.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R

/// 「全て / 未読のみ」フィルターと右端のストックボタン（iOS FilterFooterView の移植）。
/// フィードページ・記事一覧ページの下部に共通で表示する。
@Composable
fun FilterFooter(
    unreadOnly: Boolean,
    onUnreadOnlyChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    onStockTap: (() -> Unit)? = null,
) {
    Surface(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterButton(text = stringResource(R.string.filter_all), selected = !unreadOnly) {
                onUnreadOnlyChange(false)
            }
            FilterButton(text = stringResource(R.string.filter_unread_only), selected = unreadOnly) {
                onUnreadOnlyChange(true)
            }
            Spacer(modifier = Modifier.weight(1f))
            if (onStockTap != null) {
                OutlinedIconButton(onClick = onStockTap) {
                    Icon(Icons.Filled.Inventory2, contentDescription = stringResource(R.string.stock_content_description))
                }
            }
        }
    }
}

@Composable
private fun FilterButton(text: String, selected: Boolean, onClick: () -> Unit) {
    if (selected) {
        Button(onClick = onClick) { Text(text) }
    } else {
        OutlinedButton(onClick = onClick) { Text(text) }
    }
}
