package com.mtkg.gogai.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.ArticleFilter

/// 「全て / 未読のみ / like / dislike」フィルターと右端のストックボタン（iOS FilterFooterView の移植）。
/// フィードページ・記事一覧ページの下部に共通で表示する。
/// 並ぶ数が多くラベル付きでは横幅が足りないためアイコンのみにしている。
@Composable
fun FilterFooter(
    filter: ArticleFilter,
    onFilterChange: (ArticleFilter) -> Unit,
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
            ArticleFilter.entries.forEach { candidate ->
                FilterIconButton(
                    icon = candidate.icon,
                    contentDescription = stringResource(candidate.labelRes),
                    selected = filter == candidate,
                ) {
                    onFilterChange(candidate)
                }
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

private val ArticleFilter.icon: ImageVector
    get() = when (this) {
        ArticleFilter.All -> Icons.AutoMirrored.Filled.List
        ArticleFilter.Unread -> Icons.Filled.MarkEmailUnread
        ArticleFilter.Liked -> Icons.Filled.ThumbUp
        ArticleFilter.Disliked -> Icons.Filled.ThumbDown
    }

private val ArticleFilter.labelRes: Int
    get() = when (this) {
        ArticleFilter.All -> R.string.filter_all
        ArticleFilter.Unread -> R.string.filter_unread_only
        ArticleFilter.Liked -> R.string.filter_liked
        ArticleFilter.Disliked -> R.string.filter_disliked
    }

@Composable
private fun FilterIconButton(
    icon: ImageVector,
    contentDescription: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    if (selected) {
        FilledIconButton(onClick = onClick) { Icon(icon, contentDescription = contentDescription) }
    } else {
        OutlinedIconButton(onClick = onClick) { Icon(icon, contentDescription = contentDescription) }
    }
}
