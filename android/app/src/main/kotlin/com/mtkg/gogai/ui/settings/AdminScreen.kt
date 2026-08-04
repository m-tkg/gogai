package com.mtkg.gogai.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import com.mtkg.gogai.R
import com.mtkg.gogai.network.ServerUrlManager
import com.mtkg.gogai.network.isSuccessfulResponse
import com.mtkg.gogai.store.ArticleStore
import com.mtkg.gogai.store.FeedStore
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.store.SettingsStore
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Request

private enum class RestartPhase { Building, Waiting }

/// 管理画面（iOS AdminView の移植）。アップデート確認 + 「git pull して再起動」の2段階待機。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminScreen(
    settingsStore: SettingsStore,
    serverUrlManager: ServerUrlManager,
    groupStore: GroupStore,
    feedStore: FeedStore,
    articleStore: ArticleStore,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val updateCheck by settingsStore.updateCheck.collectAsState()

    var isChecking by remember { mutableStateOf(false) }
    var isWaitingForRestart by remember { mutableStateOf(false) }
    var restartPhase by remember { mutableStateOf(RestartPhase.Building) }
    var restartCheckCount by remember { mutableIntStateOf(0) }
    var restartOutput by remember { mutableStateOf<String?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        settingsStore.checkUpdate()
    }

    fun checkUpdate() {
        scope.launch {
            isChecking = true
            errorMessage = null
            try {
                settingsStore.checkUpdate()
                settingsStore.error.value?.let { errorMessage = it.message ?: it.toString() }
            } finally {
                isChecking = false
            }
        }
    }

    /// /health に到達できるまで1秒間隔で最大120回（約2分）ポーリングする。
    /// iOS の ephemeral URLSession 相当として、コネクションプールを実質無効化し
    /// 再起動直後の stale コネクションを再利用しない専用クライアントを使う。
    suspend fun waitForServer() {
        val baseUrl = serverUrlManager.resolvedUrl.value ?: return
        val healthUrl = baseUrl.newBuilder().addPathSegment("health").build()
        val pollingClient = OkHttpClient.Builder()
            .connectionPool(ConnectionPool(0, 1, TimeUnit.NANOSECONDS))
            .callTimeout(1, TimeUnit.SECONDS)
            .build()
        repeat(120) {
            delay(1000)
            restartCheckCount += 1
            val healthy = try {
                val request = Request.Builder().url(healthUrl).build()
                pollingClient.isSuccessfulResponse(request)
            } catch (e: Exception) {
                false
            }
            if (healthy) return
        }
    }

    fun restart() {
        scope.launch {
            restartPhase = RestartPhase.Building
            restartCheckCount = 0
            isWaitingForRestart = true
            errorMessage = null
            try {
                restartOutput = settingsStore.restart()
            } catch (e: Exception) {
                isWaitingForRestart = false
                errorMessage = e.message ?: e.toString()
                return@launch
            }

            restartPhase = RestartPhase.Waiting
            waitForServer()
            isWaitingForRestart = false

            // サーバーが戻ったら全ストアを再フェッチ（接続を復活させる）
            groupStore.fetchGroups()
            feedStore.fetchFeeds()
            articleStore.fetchArticles()
            settingsStore.checkUpdate()
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.admin_title)) },
                navigationIcon = { TextButton(onClick = onBack) { Text(stringResource(R.string.admin_back)) } },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Text(stringResource(R.string.admin_section_update), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))

            updateCheck?.let { check ->
                LabeledValueRow(stringResource(R.string.admin_local_label), check.local)
                LabeledValueRow(stringResource(R.string.admin_remote_label), check.remote)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(stringResource(R.string.admin_section_update))
                    if (check.hasUpdate) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                            Text(stringResource(R.string.admin_update_available), color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 4.dp))
                        }
                    } else {
                        Text(stringResource(R.string.admin_update_latest), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
            }

            OutlinedButton(onClick = { checkUpdate() }, enabled = !isChecking) {
                if (isChecking) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.admin_check_update), modifier = Modifier.padding(start = 8.dp))
                } else {
                    Text(stringResource(R.string.admin_check_update))
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 20.dp))

            Text(stringResource(R.string.admin_section_restart), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp))

            if (isWaitingForRestart) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 8.dp)) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text(
                        text = if (restartPhase == RestartPhase.Building) {
                            stringResource(R.string.admin_restart_building)
                        } else {
                            stringResource(R.string.admin_restart_waiting, restartCheckCount)
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            } else {
                restartOutput?.let { output ->
                    Text(
                        text = output,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                }
            }

            OutlinedButton(onClick = { restart() }, enabled = !isWaitingForRestart) {
                Text(stringResource(R.string.admin_restart_action), color = MaterialTheme.colorScheme.error)
            }
            Text(
                text = stringResource(R.string.admin_restart_footer),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )

            errorMessage?.let { message ->
                HorizontalDivider(modifier = Modifier.padding(vertical = 20.dp))
                Text(message, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun LabeledValueRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
    }
}
