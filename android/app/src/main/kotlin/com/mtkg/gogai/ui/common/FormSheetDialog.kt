package com.mtkg.gogai.ui.common

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Group
import kotlinx.coroutines.launch

/// 追加・編集フォーム共通のシェル（iOS FormSheet の移植）。
/// タイトル・キャンセル/確定・送信中インジケータ・インラインエラー表示を提供する。
/// SwiftUI の Form + NavigationStack に相当する内容を ModalBottomSheet 上に構成する。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FormSheetDialog(
    title: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    onSubmit: suspend () -> Unit,
    modifier: Modifier = Modifier,
    confirmEnabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var isSubmitting by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    fun dismiss() {
        scope.launch { sheetState.hide() }.invokeOnCompletion {
            if (!sheetState.isVisible) onDismiss()
        }
    }

    fun submit() {
        scope.launch {
            isSubmitting = true
            errorMessage = null
            try {
                onSubmit()
                dismiss()
            } catch (e: Exception) {
                errorMessage = e.message ?: "エラーが発生しました"
            } finally {
                isSubmitting = false
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { dismiss() }) {
                    Text(stringResource(R.string.cancel))
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            content()

            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(text = errorMessage.orEmpty(), color = MaterialTheme.colorScheme.error)
            }

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = { submit() },
                enabled = confirmEnabled && !isSubmitting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text(confirmLabel)
                }
            }
        }
    }
}

/// グループ選択の共通セクション（フィード追加・編集で使用。iOS GroupPickerSection の移植）。
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupPickerSection(
    groups: List<Group>,
    selectedGroupId: Int?,
    onSelect: (Int?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val noneLabel = stringResource(R.string.group_picker_none)
    val selectedLabel = groups.firstOrNull { it.id == selectedGroupId }?.name ?: noneLabel

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = stringResource(R.string.group_picker_section),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(4.dp))
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
            OutlinedTextField(
                value = selectedLabel,
                onValueChange = {},
                readOnly = true,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(
                    text = { Text(noneLabel) },
                    onClick = { onSelect(null); expanded = false },
                )
                groups.forEach { group ->
                    DropdownMenuItem(
                        text = { Text(group.name) },
                        onClick = { onSelect(group.id); expanded = false },
                    )
                }
            }
        }
    }
}
