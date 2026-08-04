package com.mtkg.gogai.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.BuildConfig
import com.mtkg.gogai.R
import com.mtkg.gogai.ai.AiProvider
import com.mtkg.gogai.ai.currentAiProvider
import com.mtkg.gogai.ai.setCurrentAiProvider
import com.mtkg.gogai.cache.AppCache
import com.mtkg.gogai.cache.KeyValueStore
import com.mtkg.gogai.cache.SecretStore
import com.mtkg.gogai.network.ServerUrlManager
import com.mtkg.gogai.store.SettingsStore
import kotlinx.coroutines.launch

/// 設定画面（iOS SettingsView の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settingsStore: SettingsStore,
    serverUrlManager: ServerUrlManager,
    keyValueStore: KeyValueStore,
    secretStore: SecretStore,
    appCache: AppCache,
    onClose: () -> Unit,
    onNavigateAdmin: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val serverUrl by serverUrlManager.serverUrl.collectAsState()
    val resolvedUrl by serverUrlManager.resolvedUrl.collectAsState()
    val appContainer = com.mtkg.gogai.ui.ai.LocalAppContainer.current

    var retentionDaysText by remember { mutableStateOf("") }
    var adminSecretText by remember { mutableStateOf("") }
    var aiProvider by remember { mutableStateOf(AiProvider.Automatic) }
    var aiProviderMenuExpanded by remember { mutableStateOf(false) }
    var openAiKeyText by remember { mutableStateOf("") }
    var geminiKeyText by remember { mutableStateOf("") }
    var claudeKeyText by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var cacheSize by remember { mutableStateOf(0L) }
    var isCacheCleared by remember { mutableStateOf(false) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var showClearCacheConfirm by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val invalidValueMessage = stringResource(R.string.settings_invalid_value)

    LaunchedEffect(Unit) {
        settingsStore.fetchSettings()
        retentionDaysText = (settingsStore.settings.value?.retention_days ?: 180).toString()
        adminSecretText = secretStore.get(SecretStore.ADMIN_SECRET).orEmpty()
        aiProvider = currentAiProvider(keyValueStore)
        openAiKeyText = secretStore.get(SecretStore.OPENAI_API_KEY).orEmpty()
        geminiKeyText = secretStore.get(SecretStore.GEMINI_API_KEY).orEmpty()
        claudeKeyText = secretStore.get(SecretStore.CLAUDE_API_KEY).orEmpty()
        cacheSize = appCache.totalSize
    }

    fun saveSecret(key: String, value: String) {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) secretStore.remove(key) else secretStore.set(key, trimmed)
    }

    fun save() {
        val days = retentionDaysText.toIntOrNull()
        if (days == null) {
            saveError = invalidValueMessage
            return
        }
        scope.launch {
            isSaving = true
            saveError = null
            try {
                saveSecret(SecretStore.ADMIN_SECRET, adminSecretText)
                setCurrentAiProvider(keyValueStore, aiProvider)
                saveSecret(SecretStore.OPENAI_API_KEY, openAiKeyText)
                saveSecret(SecretStore.GEMINI_API_KEY, geminiKeyText)
                saveSecret(SecretStore.CLAUDE_API_KEY, claudeKeyText)
                settingsStore.updateRetentionDays(days)
                // API キー・プロバイダ変更を AI 配線に即反映する
                appContainer?.refreshAiWiring()
                onClose()
            } catch (e: Exception) {
                saveError = e.message ?: e.toString()
            } finally {
                isSaving = false
            }
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                navigationIcon = { TextButton(onClick = onClose) { Text(stringResource(R.string.settings_close)) } },
                actions = { TextButton(onClick = { save() }, enabled = !isSaving) { Text(stringResource(R.string.save)) } },
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
            SectionHeader(stringResource(R.string.settings_section_connection))
            LabeledValueRow(
                label = stringResource(R.string.server_setup_url_label),
                value = serverUrl ?: stringResource(R.string.settings_server_url_unset),
            )
            if (resolvedUrl != null && resolvedUrl.toString() != serverUrl) {
                Text(
                    text = stringResource(R.string.settings_server_url_resolved, resolvedUrl.toString()),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(onClick = { showResetConfirm = true }) {
                Text(stringResource(R.string.settings_reset_server), color = MaterialTheme.colorScheme.error)
            }

            SectionDivider()

            SectionHeader(stringResource(R.string.settings_section_data))
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.settings_retention_days_label), modifier = Modifier.weight(1f))
                OutlinedTextField(
                    value = retentionDaysText,
                    onValueChange = { retentionDaysText = it },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    textStyle = MaterialTheme.typography.bodyMedium.copy(textAlign = TextAlign.End),
                    modifier = Modifier.width(80.dp),
                    singleLine = true,
                )
                Text(stringResource(R.string.settings_retention_days_unit), modifier = Modifier.padding(start = 4.dp))
            }
            Spacer(modifier = Modifier.height(8.dp))
            LabeledValueRow(label = stringResource(R.string.settings_cache_size_label), value = formatFileSize(cacheSize))
            Spacer(modifier = Modifier.height(8.dp))
            if (isCacheCleared) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Text(
                        stringResource(R.string.settings_cache_cleared),
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            } else {
                OutlinedButton(onClick = { showClearCacheConfirm = true }) {
                    Text(stringResource(R.string.settings_clear_cache), color = MaterialTheme.colorScheme.error)
                }
            }
            Text(
                text = stringResource(R.string.settings_data_footer),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )

            SectionDivider()

            SectionHeader(stringResource(R.string.settings_section_ai))
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.settings_ai_provider_label), modifier = Modifier.weight(1f))
                Box {
                    TextButton(onClick = { aiProviderMenuExpanded = true }) { Text(aiProvider.label) }
                    DropdownMenu(expanded = aiProviderMenuExpanded, onDismissRequest = { aiProviderMenuExpanded = false }) {
                        AiProvider.entries.forEach { provider ->
                            DropdownMenuItem(
                                text = { Text(provider.label) },
                                onClick = { aiProvider = provider; aiProviderMenuExpanded = false },
                            )
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = openAiKeyText,
                onValueChange = { openAiKeyText = it },
                label = { Text(stringResource(R.string.settings_openai_key_label)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = geminiKeyText,
                onValueChange = { geminiKeyText = it },
                label = { Text(stringResource(R.string.settings_gemini_key_label)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = claudeKeyText,
                onValueChange = { claudeKeyText = it },
                label = { Text(stringResource(R.string.settings_claude_key_label)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = stringResource(R.string.settings_ai_footer),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )

            saveError?.let { message ->
                Spacer(modifier = Modifier.height(12.dp))
                Text(message, color = MaterialTheme.colorScheme.error)
            }

            SectionDivider()

            SectionHeader(stringResource(R.string.settings_section_admin_secret))
            OutlinedTextField(
                value = adminSecretText,
                onValueChange = { adminSecretText = it },
                label = { Text(stringResource(R.string.settings_admin_secret_placeholder)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = stringResource(R.string.settings_admin_secret_footer),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = onNavigateAdmin) {
                Icon(Icons.Filled.Dns, contentDescription = null)
                Text(stringResource(R.string.admin_title), modifier = Modifier.padding(start = 8.dp))
            }

            SectionDivider()

            SectionHeader(stringResource(R.string.settings_section_app_info))
            LabeledValueRow(label = stringResource(R.string.settings_version_label), value = BuildConfig.VERSION_NAME)
        }
    }

    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text(stringResource(R.string.settings_reset_server_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    showResetConfirm = false
                    serverUrlManager.clearServerUrl()
                }) { Text(stringResource(R.string.settings_reset_action)) }
            },
            dismissButton = {
                TextButton(onClick = { showResetConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    if (showClearCacheConfirm) {
        AlertDialog(
            onDismissRequest = { showClearCacheConfirm = false },
            title = { Text(stringResource(R.string.settings_clear_cache_confirm_title)) },
            confirmButton = {
                TextButton(onClick = {
                    showClearCacheConfirm = false
                    appCache.clearAll()
                    cacheSize = appCache.totalSize
                    isCacheCleared = true
                }) { Text(stringResource(R.string.feed_delete)) }
            },
            dismissButton = {
                TextButton(onClick = { showClearCacheConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(bottom = 8.dp),
    )
}

@Composable
private fun SectionDivider() {
    HorizontalDivider(modifier = Modifier.padding(vertical = 20.dp))
}

@Composable
private fun LabeledValueRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
    }
}

/// iOS ByteCountFormatter(countStyle: .file) 相当の簡易実装（10進 1000 単位）。
@Composable
private fun formatFileSize(bytes: Long): String {
    if (bytes < 1000) return stringResource(R.string.settings_cache_size_bytes, bytes.toInt())
    val units = listOf("KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unitIndex = -1
    while (value >= 1000 && unitIndex < units.size - 1) {
        value /= 1000
        unitIndex++
    }
    return "%.1f %s".format(value, units[unitIndex])
}
