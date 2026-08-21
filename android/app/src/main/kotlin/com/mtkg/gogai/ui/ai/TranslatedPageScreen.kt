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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.mtkg.gogai.R
import com.mtkg.gogai.ai.AiError
import com.mtkg.gogai.ai.PageBatchTranslator
import com.mtkg.gogai.ai.PageTranslator
import com.mtkg.gogai.ai.SentenceSplitter
import com.mtkg.gogai.ai.TextGenerating
import com.mtkg.gogai.ai.TranslationMix
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.store.StockStore
import kotlin.coroutines.resume
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private enum class TranslationStatus { Loading, Translating, Done, Failed }

@Serializable
private data class SetTranslationsPayload(val i: List<Int>, val t: List<String>)

@Serializable
private data class SetShowPayload(val i: List<Int>, val s: List<Boolean>)

/**
 * レイアウト保持のページ内翻訳を行うフルスクリーンオーバーレイ（iOS FMTranslatedPageView /
 * TranslatedPageModel, AI/FMTranslatedPageView.swift・AI/TranslatedPageModel.swift の移植）。
 *
 * WebView で stock.url をロードし、assets/translator/extract.js を注入してテキストノードを
 * 収集、[SentenceSplitter] で文単位に分割して `__gogaiSplit` で span 化、[PageTranslator] で
 * 保存済み訳文の復元と新規翻訳を行い、`__gogaiSetTr` で DOM に書き戻す。全完了後にサーバーへ
 * 保存する（StockStore.saveTranslation）。
 * 表示は設定した割合の文だけ訳文にするミックス表示（`__gogaiSetShow`）。各文はページ上で
 * タップすると原文 ⇄ 訳文を個別に切り替えられる（切り替えはページ側 JS が持つ）。
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
    var hasTranslations by remember { mutableStateOf(false) }
    var sentenceCount by remember { mutableIntStateOf(0) }
    var mixRatio by remember {
        mutableIntStateOf(container?.keyValueStore?.let { TranslationMix.savedRatio(it) } ?: TranslationMix.DEFAULT_RATIO)
    }
    var mixOffset by remember { mutableIntStateOf(0) }
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
        hasTranslations = false
        stockStore.pauseSummaryQueueForTranslation()
        try {
            val extractScript = readExtractScript(webView)
            val rawResult = webView.evaluateJavascriptSuspend(extractScript)
            val nodeTexts = decodeTextsArray(rawResult)
            // 文単位に分割して span 化する。以降の index はすべて文の通し番号
            val pieces = nodeTexts.map { SentenceSplitter.split(it) }
            val texts = pieces.flatten().map { it.trim() }
            sentenceCount = texts.size
            if (texts.isEmpty()) {
                status = TranslationStatus.Done
                return
            }
            webView.evaluateJavascriptSuspend("window.__gogaiSplit(${Json.encodeToString(pieces)}); true;")
            applyMix(webView, texts.size, mixRatio, mixOffset)

            val savedJson = if (forceRetranslate) null else stockStore.fetchTranslation(stock.id)?.segments
            val generator: TextGenerating = container?.currentTextGenerator()
                ?: TextGenerating { _, _ -> throw AiError.AiUnavailable }
            val translator = PageTranslator(PageBatchTranslator(generator))

            val result = translator.translate(texts, savedJson, pageTitle) { completed, total ->
                translatedCount = completed
                totalCount = total
            }

            if (result.merged.isNotEmpty()) {
                setTranslations(webView, result.merged)
                hasTranslations = true
            }
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
                horizontalAlignment = Alignment.End,
            ) {
                val isMixEnabled = status == TranslationStatus.Done && hasTranslations
                suspend fun changeRatio(delta: Int) {
                    val webView = webViewRef ?: return
                    val next = TranslationMix.clamp(mixRatio + delta)
                    if (next == mixRatio) return
                    mixRatio = next
                    container?.keyValueStore?.let { TranslationMix.saveRatio(it, next) }
                    applyMix(webView, sentenceCount, mixRatio, mixOffset)
                }
                CircleIconButton(
                    icon = Icons.Filled.Shuffle,
                    contentDescription = stringResource(R.string.stock_translate_reshuffle_content_description),
                    enabled = isMixEnabled && mixRatio > TranslationMix.MIN_RATIO && mixRatio < TranslationMix.MAX_RATIO,
                    modifier = Modifier.padding(bottom = 12.dp),
                ) {
                    val webView = webViewRef ?: return@CircleIconButton
                    scope.launch {
                        mixOffset += 1
                        applyMix(webView, sentenceCount, mixRatio, mixOffset)
                    }
                }
                MixRatioStepper(
                    ratio = mixRatio,
                    enabled = isMixEnabled,
                    onDecrease = { scope.launch { changeRatio(-TranslationMix.STEP) } },
                    onIncrease = { scope.launch { changeRatio(TranslationMix.STEP) } },
                    modifier = Modifier.padding(bottom = 12.dp),
                )
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

/// 訳文で表示する文の割合を 10% 刻みで増減するカプセル（iOS PageTranslationFloatingButtons の mixRatioStepper 相当）
@Composable
private fun MixRatioStepper(
    ratio: Int,
    enabled: Boolean,
    onDecrease: () -> Unit,
    onIncrease: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.height(48.dp),
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        tonalElevation = 3.dp,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDecrease, enabled = enabled && ratio > TranslationMix.MIN_RATIO, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Filled.Remove, contentDescription = stringResource(R.string.stock_translate_mix_decrease_content_description))
            }
            Text(
                text = stringResource(R.string.stock_translate_mix_ratio_label, ratio),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.widthIn(min = 56.dp),
                textAlign = TextAlign.Center,
            )
            IconButton(onClick = onIncrease, enabled = enabled && ratio < TranslationMix.MAX_RATIO, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.stock_translate_mix_increase_content_description))
            }
        }
    }
}

/// 訳文を文 index ごとにページへ渡す（表示するかどうかは __gogaiSetShow のフラグに従う）
private suspend fun setTranslations(webView: WebView, translations: Map<Int, String>) {
    if (translations.isEmpty()) return
    val indices = translations.keys.toList()
    val texts = indices.map { translations.getValue(it) }
    val payloadJson = Json.encodeToString(SetTranslationsPayload.serializer(), SetTranslationsPayload(i = indices, t = texts))
    webView.evaluateJavascriptSuspend("window.__gogaiSetTr($payloadJson); true;")
}

/// 現在の割合・オフセットから各文の表示フラグを算出してページに送る（TranslationMix と同じ規則）
private suspend fun applyMix(webView: WebView, sentenceCount: Int, ratio: Int, offset: Int) {
    if (sentenceCount <= 0) return
    val indices = (0 until sentenceCount).toList()
    val flags = indices.map { TranslationMix.isTranslated(it, ratio, offset) }
    val payloadJson = Json.encodeToString(SetShowPayload.serializer(), SetShowPayload(i = indices, s = flags))
    webView.evaluateJavascriptSuspend("window.__gogaiSetShow($payloadJson); true;")
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
