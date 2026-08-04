package com.mtkg.gogai.ui.ai

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R

/// AI アクション（要約・翻訳）の進行状態（iOS LocalAIResultSheet の状態遷移に相当）。
sealed class AiActionState {
    data object Generating : AiActionState()
    data class Success(val text: String) : AiActionState()
    data class Failed(val message: String) : AiActionState()
}

/**
 * AI アクションの結果を表示するボトムシート（iOS LocalAIResultSheet の移植）。
 * 進行中はインジケータ、成功時は本文 + コピー、失敗時はエラーメッセージを表示する。
 * サーバーには何も保存しない（iOS のローカル AI 結果表示と同じ、都度その場限りの表示）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AiResultSheet(title: String, state: AiActionState, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val clipboard = LocalClipboardManager.current

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
        ) {
            Text(text = title, style = MaterialTheme.typography.titleLarge)
            Spacer(modifier = Modifier.height(16.dp))

            when (state) {
                is AiActionState.Generating -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text(
                            text = stringResource(R.string.article_ai_generating),
                            modifier = Modifier.padding(start = 12.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                is AiActionState.Success -> {
                    SelectionContainer {
                        Text(
                            text = state.text,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(max = 320.dp)
                                .verticalScroll(rememberScrollState()),
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    TextButton(onClick = { clipboard.setText(AnnotatedString(state.text)) }) {
                        Icon(Icons.Filled.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(
                            text = stringResource(R.string.article_ai_copy),
                            modifier = Modifier.padding(start = 8.dp),
                        )
                    }
                }
                is AiActionState.Failed -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Text(
                            text = state.message,
                            modifier = Modifier.padding(start = 8.dp),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
        }
    }
}
