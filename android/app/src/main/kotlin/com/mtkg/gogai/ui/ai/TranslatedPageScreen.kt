package com.mtkg.gogai.ui.ai

import android.annotation.SuppressLint
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.mtkg.gogai.R
import com.mtkg.gogai.ai.AiError
import com.mtkg.gogai.ai.PageBatchTranslator
import com.mtkg.gogai.ai.PageTranslator
import com.mtkg.gogai.ai.TextGenerating
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.store.StockStore
import kotlin.coroutines.resume
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

private enum class TranslationStatus { Loading, Translating, Done, Failed }

@Serializable
private data class BulkApplyPayload(val i: List<Int>, val t: List<String>)

/**
 * レイアウト保持のページ内翻訳を行うフルスクリーンオーバーレイ（iOS FMTranslatedPageView /
 * TranslatedPageModel, AI/FMTranslatedPageView.swift・AI/TranslatedPageModel.swift の移植）。
 *
 * WebView で stock.url をロードし、assets/translator/extract.js を注入してテキストノードを
 * 収集、[PageTranslator] で保存済み訳文の復元と新規翻訳を行い、`__gogaiApplyAll` で DOM に
 * 書き戻す。全完了後にサーバーへ保存する（StockStore.saveTranslation）。
 *
 * app/GogaiNavHost.kt を編集できない制約のため、NavHost に新しい route を追加せず、
 * 呼び出し元（StockListScreen/StockDetailScreen）がローカル状態でこの Composable の表示を
 * 切り替える形にしている。表示自体はここで全画面 Dialog として自己完結させる。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TranslatedPageScreen(stock: Stock, stockStore: StockStore, onClose: () -> Unit) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val pageTitle = stock.title ?: stock.url

    var status by remember { mutableStateOf(TranslationStatus.Loading) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var translatedCount by remember { mutableIntStateOf(0) }
    var totalCount by remember { mutableIntStateOf(0) }
    var isShowingOriginal by remember { mutableStateOf(false) }
    var currentTranslations by remember { mutableStateOf<Map<Int, String>>(emptyMap()) }
    var originalTexts by remember { mutableStateOf<List<String>>(emptyList()) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var pageLoaded by remember { mutableStateOf(false) }
    var hasStarted by remember { mutableStateOf(false) }

    val aiUnavailableNotice = stringResource(R.string.stock_translate_ai_unavailable_notice)

    suspend fun runTranslationFlow(forceRetranslate: Boolean) {
        val webView = webViewRef ?: return
        status = TranslationStatus.Translating
        errorMessage = null
        translatedCount = 0
        totalCount = 0
        stockStore.pauseSummaryQueueForTranslation()
        try {
            val extractScript = readExtractScript(webView)
            val rawResult = webView.evaluateJavascriptSuspend(extractScript)
            val texts = decodeTextsArray(rawResult)
            originalTexts = texts
            if (texts.isEmpty()) {
                status = TranslationStatus.Done
                return
            }

            val savedJson = if (forceRetranslate) null else stockStore.fetchTranslation(stock.id)?.segments
            val generator: TextGenerating = container?.currentTextGenerator()
                ?: TextGenerating { _, _ -> throw AiError.AiUnavailable }
            val translator = PageTranslator(PageBatchTranslator(generator))

            val result = translator.translate(texts, savedJson, pageTitle) { completed, total ->
                translatedCount = completed
                totalCount = total
            }

            if (result.merged.isNotEmpty()) {
                applyAll(webView, result.merged)
                currentTranslations = result.merged
            }
            isShowingOriginal = false
            result.payloadJson?.let { json ->
                runCatching { stockStore.saveTranslation(stock.id, json) }
            }
            status = TranslationStatus.Done
        } catch (e: Exception) {
            status = TranslationStatus.Failed
            errorMessage = e.message ?: e.toString()
        } finally {
            stockStore.resumeSummaryQueueAfterTranslation()
        }
    }

    LaunchedEffect(pageLoaded) {
        if (pageLoaded && !hasStarted) {
            hasStarted = true
            runTranslationFlow(forceRetranslate = false)
        }
    }

    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = true
                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView, url: String?) {
                                pageLoaded = true
                            }

                            override fun onReceivedError(
                                view: WebView,
                                request: WebResourceRequest,
                                error: WebResourceError,
                            ) {
                                if (request.isForMainFrame) {
                                    status = TranslationStatus.Failed
                                    errorMessage = error.description?.toString()
                                }
                            }
                        }
                        webViewRef = this
                        loadUrl(stock.url)
                    }
                },
            )

            TranslationStatusBar(
                status = status,
                translatedCount = translatedCount,
                totalCount = totalCount,
                errorMessage = errorMessage,
                aiUnavailable = container?.aiAvailable() != true,
                aiUnavailableNotice = aiUnavailableNotice,
                modifier = Modifier.align(Alignment.TopCenter),
            )

            Column(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(20.dp),
            ) {
                if (currentTranslations.isNotEmpty()) {
                    CircleIconButton(
                        icon = Icons.Filled.Translate,
                        contentDescription = if (isShowingOriginal) {
                            stringResource(R.string.stock_translate_show_translation_content_description)
                        } else {
                            stringResource(R.string.stock_translate_show_original_content_description)
                        },
                        modifier = Modifier.padding(bottom = 12.dp),
                    ) {
                        val webView = webViewRef ?: return@CircleIconButton
                        scope.launch {
                            if (isShowingOriginal) {
                                applyAll(webView, currentTranslations)
                                isShowingOriginal = false
                            } else {
                                val originals = currentTranslations.keys.associateWith { index ->
                                    originalTexts.getOrNull(index) ?: ""
                                }
                                applyAll(webView, originals)
                                isShowingOriginal = true
                            }
                        }
                    }
                }
                CircleIconButton(
                    icon = Icons.Filled.Refresh,
                    contentDescription = stringResource(R.string.stock_translate_retranslate_content_description),
                    enabled = status == TranslationStatus.Done || status == TranslationStatus.Failed,
                    modifier = Modifier.padding(bottom = 12.dp),
                ) {
                    scope.launch { runTranslationFlow(forceRetranslate = true) }
                }
                CircleIconButton(
                    icon = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.stock_translate_close_content_description),
                ) {
                    onClose()
                }
            }
        }
    }
}

@Composable
private fun TranslationStatusBar(
    status: TranslationStatus,
    translatedCount: Int,
    totalCount: Int,
    errorMessage: String?,
    aiUnavailable: Boolean,
    aiUnavailableNotice: String,
    modifier: Modifier = Modifier,
) {
    val text = when (status) {
        TranslationStatus.Loading -> stringResource(R.string.stock_translate_status_loading)
        TranslationStatus.Translating -> if (totalCount > 0) {
            stringResource(R.string.stock_translate_status_translating, translatedCount, totalCount)
        } else {
            stringResource(R.string.stock_translate_status_loading)
        }
        TranslationStatus.Done -> stringResource(R.string.stock_translate_status_done)
        TranslationStatus.Failed -> stringResource(R.string.stock_translate_status_failed, errorMessage.orEmpty())
    }
    Surface(modifier = modifier.fillMaxWidth(), tonalElevation = 3.dp) {
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (status == TranslationStatus.Loading || status == TranslationStatus.Translating) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                }
                Text(
                    text = text,
                    modifier = Modifier.padding(start = 8.dp),
                    style = MaterialTheme.typography.labelLarge,
                )
            }
            if (aiUnavailable) {
                Text(
                    text = aiUnavailableNotice,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
        }
    }
}

/// 48dp の円形アイコンボタン（iOS CircleIconButton 相当）。
@Composable
private fun CircleIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    FilledIconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.size(48.dp),
    ) {
        Icon(icon, contentDescription = contentDescription)
    }
}

private suspend fun applyAll(webView: WebView, translations: Map<Int, String>) {
    if (translations.isEmpty()) return
    val indices = translations.keys.toList()
    val texts = indices.map { translations.getValue(it) }
    val payloadJson = Json.encodeToString(BulkApplyPayload.serializer(), BulkApplyPayload(i = indices, t = texts))
    webView.evaluateJavascriptSuspend("window.__gogaiApplyAll($payloadJson); true;")
}

private fun decodeTextsArray(raw: String?): List<String> {
    if (raw.isNullOrEmpty() || raw == "null") return emptyList()
    return runCatching { Json.decodeFromString<List<String>>(raw) }.getOrDefault(emptyList())
}

private fun readExtractScript(webView: WebView): String =
    webView.context.assets.open("translator/extract.js").bufferedReader().use { it.readText() }

/// WebView.evaluateJavascript をコルーチンから呼べるようにする（メインスレッド前提）。
private suspend fun WebView.evaluateJavascriptSuspend(script: String): String =
    suspendCancellableCoroutine { continuation ->
        evaluateJavascript(script) { result -> continuation.resume(result ?: "null") }
    }
