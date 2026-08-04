package com.mtkg.gogai.share

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.model.StockCategory
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.await
import com.mtkg.gogai.repository.StockRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/// 共有シートから URL をストックする最小限の UI（iOS ShareStockView の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareStockScreen(
    url: String,
    initialTitleGuess: String?,
    client: ApiClient?,
    httpClient: OkHttpClient,
    onFinish: () -> Unit,
) {
    var titleText by remember { mutableStateOf(initialTitleGuess ?: "") }
    var sourceText by remember { mutableStateOf(defaultSource()) }
    var categories by remember { mutableStateOf<List<StockCategory>>(emptyList()) }
    var categoryMenuExpanded by remember { mutableStateOf(false) }
    var existingStock by remember { mutableStateOf<Stock?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val noServerConfiguredMessage = stringResource(R.string.share_no_server_configured)
    val saveFailedTemplate = stringResource(R.string.share_save_failed)

    LaunchedEffect(url) {
        // タイトルの手がかりが無い場合のみ、最終手段としてページを取得して <title> を抽出する
        // （iOS ShareViewController.fetchPageTitle 相当。拡張プロセスと違い WebView 制約は無いが、
        // 同じく軽量な取得に留める）。
        if (initialTitleGuess == null) {
            titleText = fetchPageTitle(httpClient, url) ?: ""
        }
        if (client != null) {
            categories = runCatching { StockRepository(client).fetchCategories() }.getOrDefault(emptyList())
            existingStock = runCatching { StockRepository(client).lookup(url) }.getOrNull()
        }
    }

    fun save() {
        scope.launch {
            isSaving = true
            errorMessage = null
            try {
                if (client == null) throw IllegalStateException(noServerConfiguredMessage)
                val trimmedSource = sourceText.trim()
                val trimmedTitle = titleText.trim()
                StockRepository(client).create(
                    url = url,
                    title = trimmedTitle.ifEmpty { null },
                    source = trimmedSource.ifEmpty { null },
                )
                onFinish()
            } catch (e: Exception) {
                errorMessage = saveFailedTemplate.format(e.message ?: e.toString())
            } finally {
                isSaving = false
            }
        }
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.share_title)) },
                navigationIcon = {
                    TextButton(onClick = onFinish) { Text(stringResource(R.string.cancel)) }
                },
                actions = {
                    TextButton(onClick = { save() }, enabled = !isSaving) {
                        if (isSaving) {
                            CircularProgressIndicator(modifier = Modifier.height(16.dp))
                        } else {
                            Text(stringResource(R.string.share_save))
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(16.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
        ) {
            Text(
                text = stringResource(R.string.share_url_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = url,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            existingStock?.let { stock ->
                Row(
                    modifier = Modifier.padding(top = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary)
                    Text(
                        text = stringResource(R.string.share_already_stocked, stock.title ?: stock.url, stock.category_name),
                        color = MaterialTheme.colorScheme.tertiary,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = stringResource(R.string.stock_add_title_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = titleText,
                onValueChange = { titleText = it },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = stringResource(R.string.share_source_category_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = sourceText,
                onValueChange = { sourceText = it },
                placeholder = { Text(stringResource(R.string.share_source_placeholder)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            if (categories.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                androidx.compose.foundation.layout.Box {
                    TextButton(onClick = { categoryMenuExpanded = true }) {
                        Text(stringResource(R.string.stock_edit_pick_existing_category))
                    }
                    DropdownMenu(expanded = categoryMenuExpanded, onDismissRequest = { categoryMenuExpanded = false }) {
                        categories.forEach { category ->
                            DropdownMenuItem(
                                text = { Text(category.name) },
                                onClick = { sourceText = category.name; categoryMenuExpanded = false },
                            )
                        }
                    }
                }
            }

            errorMessage?.let { message ->
                Spacer(modifier = Modifier.height(16.dp))
                Text(message, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun defaultSource(): String = "共有"

/// URL から HTML を軽量に取得し <title> タグを抽出する（共有元のメタデータが全く取れない場合の最終手段）。
/// 先頭 64KB のみを読んで打ち切る（iOS ShareViewController.fetchPageTitle 相当）。
private suspend fun fetchPageTitle(httpClient: OkHttpClient, url: String): String? = withContext(Dispatchers.IO) {
    try {
        val client = httpClient.newBuilder().callTimeout(5, TimeUnit.SECONDS).build()
        val request = Request.Builder().url(url).build()
        val response = client.newCall(request).await()
        response.use { resp ->
            if (!resp.isSuccessful) return@withContext null
            val body = resp.body ?: return@withContext null
            val stream = body.byteStream()
            val buffer = ByteArray(65536)
            var total = 0
            while (total < buffer.size) {
                val read = stream.read(buffer, total, buffer.size - total)
                if (read == -1) break
                total += read
            }
            val html = String(buffer, 0, total, Charsets.UTF_8)
            extractTitleTag(html)
        }
    } catch (e: Exception) {
        null
    }
}
