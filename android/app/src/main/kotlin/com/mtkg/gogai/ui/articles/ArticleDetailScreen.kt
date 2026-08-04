package com.mtkg.gogai.ui.articles

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MarkEmailRead
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.ai.ArticleContentFetcher
import com.mtkg.gogai.ai.LocalArticleAI
import com.mtkg.gogai.model.Article
import com.mtkg.gogai.store.ArticleStore
import com.mtkg.gogai.ui.ai.AiActionState
import com.mtkg.gogai.ui.ai.AiResultSheet
import com.mtkg.gogai.ui.ai.LocalAppContainer
import com.mtkg.gogai.ui.common.openInCustomTabs
import com.mtkg.gogai.ui.common.shareUrl
import com.mtkg.gogai.util.HorizontalSwipeDirection
import com.mtkg.gogai.util.displayDate
import com.mtkg.gogai.util.matchHorizontalSwipe
import kotlinx.coroutines.launch

/// 概要ページ（iOS ArticleDetailView の移植）。タイトル・日付・HTML本文 + 下部バー
/// （既読トグル/前後移動）。左スワイプで記事ページ（Custom Tabs）を開く。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArticleDetailScreen(
    articleId: Int,
    articleStore: ArticleStore,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val container = LocalAppContainer.current
    val aiAvailable = container?.aiAvailable() == true

    var currentArticleId by rememberSaveable(articleId) { mutableStateOf(articleId) }
    val articles by articleStore.articles.collectAsState()
    val currentArticle = articles.firstOrNull { it.id == currentArticleId }

    // AI アクション（要約・翻訳）の結果表示（iOS BrowserView 右下オーバーレイ相当だが、
    // Android は記事ページを Custom Tabs で表示する構成上、概要ページ側に配置する）。
    // サーバーには保存しない（iOS のローカル AI 結果と同じくその場限りの表示）。
    var aiSheetTitle by remember { mutableStateOf<String?>(null) }
    var aiActionState by remember { mutableStateOf<AiActionState?>(null) }

    fun runAiAction(isTranslate: Boolean, article: Article) {
        val generator = container?.currentTextGenerator() ?: return
        aiSheetTitle = if (isTranslate) context.getString(R.string.article_ai_translate_title) else context.getString(R.string.article_ai_summarize_title)
        aiActionState = AiActionState.Generating
        scope.launch {
            val fetchedContent = article.link?.let { link ->
                runCatching { ArticleContentFetcher.fetchPlainText(link) }.getOrNull()
            } ?: article.content ?: article.summary ?: ""
            try {
                val ai = LocalArticleAI(generator)
                val result = if (isTranslate) {
                    ai.translateToJapanese(article.title, fetchedContent)
                } else {
                    ai.summarize(article.title, fetchedContent)
                }
                aiActionState = AiActionState.Success(result)
            } catch (e: Exception) {
                aiActionState = AiActionState.Failed(e.message ?: e.toString())
            }
        }
    }

    if (currentArticle == null) {
        // 記事一覧に存在しない ID（別セッションからの遷移など）は概要のみ空表示する
        Scaffold(modifier = modifier) { padding ->
            Column(modifier = Modifier.padding(padding).fillMaxSize()) {}
        }
        return
    }

    val currentIndex = articles.indexOfFirst { it.id == currentArticleId }
    val previousArticle = if (currentIndex > 0) articles.getOrNull(currentIndex - 1) else null
    val nextArticle = if (currentIndex in 0 until articles.size - 1) articles.getOrNull(currentIndex + 1) else null

    LaunchedEffect(currentArticleId) {
        if (!currentArticle.isRead) {
            articleStore.markAsRead(currentArticleId)
        }
    }

    var dx by remember { mutableFloatStateOf(0f) }
    var dy by remember { mutableFloatStateOf(0f) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.article_detail_title)) },
                actions = {
                    currentArticle.link?.let { link ->
                        IconButton(onClick = { shareUrl(context, link) }) {
                            Icon(Icons.Filled.Share, contentDescription = stringResource(R.string.article_detail_share_content_description))
                        }
                        IconButton(onClick = { openInCustomTabs(context, link) }) {
                            Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = stringResource(R.string.article_detail_open_browser_content_description))
                        }
                    }
                },
            )
        },
        bottomBar = {
            Surface(tonalElevation = 2.dp) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceAround,
                ) {
                    TextButton(onClick = {
                        scope.launch {
                            if (currentArticle.isRead) {
                                articleStore.markAsUnread(currentArticleId)
                            } else {
                                articleStore.markAsRead(currentArticleId)
                            }
                        }
                    }) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                imageVector = if (currentArticle.isRead) Icons.Filled.MarkEmailUnread else Icons.Filled.MarkEmailRead,
                                contentDescription = null,
                            )
                            Text(
                                text = if (currentArticle.isRead) stringResource(R.string.article_mark_unread) else stringResource(R.string.article_mark_read),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                    }

                    if (aiAvailable) {
                        TextButton(onClick = { runAiAction(isTranslate = false, article = currentArticle) }) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Filled.AutoAwesome, contentDescription = null)
                                Text(stringResource(R.string.article_ai_summarize_button), style = MaterialTheme.typography.labelSmall)
                            }
                        }
                        TextButton(onClick = { runAiAction(isTranslate = true, article = currentArticle) }) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Filled.Translate, contentDescription = null)
                                Text(stringResource(R.string.article_ai_translate_button), style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }

                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        TextButton(onClick = { previousArticle?.let { currentArticleId = it.id } }, enabled = previousArticle != null) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null)
                                Text(stringResource(R.string.article_detail_previous))
                            }
                        }
                        TextButton(onClick = { nextArticle?.let { currentArticleId = it.id } }, enabled = nextArticle != null) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null)
                                Text(stringResource(R.string.article_detail_next))
                            }
                        }
                    }
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .pointerInput(currentArticleId) {
                    detectDragGestures(
                        onDragStart = { dx = 0f; dy = 0f },
                        onDragEnd = {
                            val direction = matchHorizontalSwipe(dx, dy)
                            if (direction == HorizontalSwipeDirection.Left) {
                                currentArticle.link?.let { openInCustomTabs(context, it) }
                            }
                        },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            dx += dragAmount.x
                            dy += dragAmount.y
                        },
                    )
                },
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = currentArticle.title ?: stringResource(R.string.article_no_title),
                    style = MaterialTheme.typography.headlineSmall,
                )
                if (currentArticle.published_at != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(top = 8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Filled.AccessTime,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(end = 4.dp),
                        )
                        Text(
                            text = currentArticle.published_at.displayDate(),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            HorizontalDivider()

            val bodyHtml = currentArticle.content ?: currentArticle.summary
            if (bodyHtml != null) {
                HtmlContentView(html = bodyHtml, modifier = Modifier.weight(1f))
            } else {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = stringResource(R.string.article_detail_no_content),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
            }
        }
    }

    aiActionState?.let { state ->
        AiResultSheet(
            title = aiSheetTitle.orEmpty(),
            state = state,
            onDismiss = { aiActionState = null; aiSheetTitle = null },
        )
    }
}
