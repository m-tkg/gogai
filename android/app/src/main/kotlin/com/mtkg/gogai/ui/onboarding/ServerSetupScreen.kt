package com.mtkg.gogai.ui.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.network.ServerUrlManager
import com.mtkg.gogai.network.isSuccessfulResponse
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/// 初回起動時のサーバー URL 設定画面（iOS ServerSetupView の移植）。
/// 接続確認は Gist URL の解決 → GET {resolved}/health の 2xx 確認の順で行い、
/// 成功したら（Gist の場合は解決前の）元 URL を保存する。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServerSetupScreen(
    serverUrlManager: ServerUrlManager,
    httpClient: OkHttpClient,
    modifier: Modifier = Modifier,
) {
    var urlText by rememberSaveable { mutableStateOf("http://192.168.1.1:3040") }
    var isChecking by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val invalidUrlMessage = stringResource(R.string.server_setup_invalid_url)
    val connectFailedMessage = stringResource(R.string.server_setup_connect_failed)
    val connectErrorTemplate = stringResource(R.string.server_setup_connect_error)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = { TopAppBar(title = { Text(stringResource(R.string.server_setup_title)) }) },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(16.dp)
                .fillMaxWidth(),
        ) {
            Text(
                text = stringResource(R.string.server_setup_url_label),
                style = MaterialTheme.typography.labelLarge,
            )
            OutlinedTextField(
                value = urlText,
                onValueChange = { urlText = it },
                placeholder = { Text(stringResource(R.string.server_setup_url_placeholder)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = stringResource(R.string.server_setup_url_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 16.dp),
            )

            errorMessage?.let {
                Text(
                    text = it,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(bottom = 16.dp),
                )
            }

            Button(
                onClick = {
                    val trimmed = urlText.trim()
                    scope.launch {
                        isChecking = true
                        errorMessage = null
                        try {
                            if (trimmed.toHttpUrlOrNull() == null) {
                                errorMessage = invalidUrlMessage
                                return@launch
                            }
                            val resolved = serverUrlManager.resolveUrl(trimmed)
                            val healthUrl = resolved.newBuilder().addPathSegment("health").build()
                            val request = Request.Builder().url(healthUrl).build()
                            val healthy = httpClient.isSuccessfulResponse(request)
                            if (!healthy) {
                                errorMessage = connectFailedMessage
                                return@launch
                            }
                            // 元の URL（Gist URL の場合もある）を保存することで、次回起動時に
                            // 最新 URL を再取得できる
                            serverUrlManager.setServerUrl(trimmed)
                        } catch (e: Exception) {
                            errorMessage = connectErrorTemplate.format(e.message ?: e.toString())
                        } finally {
                            isChecking = false
                        }
                    }
                },
                enabled = !isChecking && urlText.trim().isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isChecking) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                } else {
                    Text(stringResource(R.string.server_setup_connect))
                }
            }
        }
    }
}
