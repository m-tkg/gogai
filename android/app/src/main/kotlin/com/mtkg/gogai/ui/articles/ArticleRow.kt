package com.mtkg.gogai.ui.articles

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MarkEmailRead
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Article
import com.mtkg.gogai.ui.theme.LikePink
import com.mtkg.gogai.util.displayDate

/// 記事一覧の1行（iOS ArticleRowView の移植）。
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ArticleRow(
    article: Article,
    faviconUrl: String?,
    groupName: String?,
    onClick: () -> Unit,
    onLongPressShare: () -> Unit,
    onToggleRead: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val backgroundColor = if (article.isRead) {
        Color.Transparent
    } else {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.05f)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(backgroundColor)
            .combinedClickable(onClick = onClick, onLongClick = onLongPressShare)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (faviconUrl != null) {
            AsyncImage(
                model = faviconUrl,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(16.dp).padding(top = 3.dp),
                error = androidx.compose.ui.graphics.vector.rememberVectorPainter(Icons.Filled.Public),
            )
        } else {
            Icon(
                imageVector = Icons.Filled.Public,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp).padding(top = 3.dp),
            )
        }

        Spacer(modifier = Modifier.width(10.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = article.title ?: stringResource(R.string.article_no_title),
                style = MaterialTheme.typography.titleMedium,
                color = if (article.isRead) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            if (article.published_at != null) {
                Row {
                    if (groupName != null) {
                        Text(
                            text = groupName,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.outline,
                        )
                        Text(" · ", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                    }
                    Text(
                        text = article.published_at.displayDate(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline,
                    )
                }
            }

            if (article.summary != null) {
                Text(
                    text = article.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            IconButton(onClick = onToggleRead) {
                Icon(
                    imageVector = if (article.isRead) Icons.Filled.MarkEmailUnread else Icons.Filled.MarkEmailRead,
                    contentDescription = if (article.isRead) {
                        stringResource(R.string.article_mark_unread)
                    } else {
                        stringResource(R.string.article_mark_read)
                    },
                    tint = if (article.isRead) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary,
                )
            }

            // like 済みのときだけ表示する（行背景は未読表現で使用済みのため触らない）
            if (article.isLiked) {
                Icon(
                    imageVector = Icons.Filled.ThumbUp,
                    contentDescription = stringResource(R.string.article_liked_content_description),
                    tint = LikePink,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}
