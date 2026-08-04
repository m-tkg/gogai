package com.mtkg.gogai.ui.sidebar

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOff
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Group
import com.mtkg.gogai.ui.theme.SecretOrange

/// グループ行（iOS GroupRowView の移植）。フォルダアイコン + 展開chevron、名前タップで
/// グループの記事一覧へ、バッジ、長押しで名前変更/シークレット切替/削除メニューを出す。
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun GroupRow(
    group: Group,
    isExpanded: Boolean,
    badgeCount: Int,
    showSecretGroups: Boolean,
    isEditing: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onToggleExpanded: () -> Unit,
    onSelect: () -> Unit,
    onToggleSecret: () -> Unit,
    onRename: (String) -> Unit,
    onDelete: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showMenu by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var renameText by remember { mutableStateOf(group.name) }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onSelect,
                onLongClick = { showMenu = true },
            )
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        IconButton(onClick = onToggleExpanded) {
            Icon(
                imageVector = if (group.isSecret) Icons.Filled.FolderOff else Icons.Filled.Folder,
                contentDescription = null,
                tint = if (group.isSecret) SecretOrange else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            imageVector = if (isExpanded) Icons.Filled.ExpandMore else Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = group.name,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.weight(1f),
        )
        com.mtkg.gogai.ui.common.UnreadCountBadge(badgeCount)

        if (showSecretGroups) {
            IconButton(onClick = onToggleSecret) {
                Icon(
                    imageVector = if (group.isSecret) Icons.Filled.Lock else Icons.Filled.LockOpen,
                    contentDescription = if (group.isSecret) stringResource(R.string.group_unset_secret) else stringResource(R.string.group_set_secret),
                    tint = if (group.isSecret) SecretOrange else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        if (isEditing) {
            IconButton(onClick = onMoveUp, enabled = canMoveUp) {
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null)
            }
            IconButton(onClick = onMoveDown, enabled = canMoveDown) {
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null)
            }
        }

        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.group_rename)) },
                leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                onClick = {
                    showMenu = false
                    renameText = group.name
                    showRenameDialog = true
                },
            )
            DropdownMenuItem(
                text = { Text(if (group.isSecret) stringResource(R.string.group_unset_secret) else stringResource(R.string.group_set_secret)) },
                leadingIcon = { Icon(if (group.isSecret) Icons.Filled.LockOpen else Icons.Filled.Lock, contentDescription = null) },
                onClick = {
                    showMenu = false
                    onToggleSecret()
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.group_delete)) },
                leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                onClick = {
                    showMenu = false
                    showDeleteConfirm = true
                },
            )
        }
    }

    if (showRenameDialog) {
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            title = { Text(stringResource(R.string.group_rename_title)) },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    label = { Text(stringResource(R.string.group_name_label)) },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showRenameDialog = false
                    onRename(renameText)
                }) {
                    Text(stringResource(R.string.change))
                }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.group_delete_confirm_title)) },
            text = { Text(stringResource(R.string.group_delete_confirm_message)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    onDelete()
                }) {
                    Text(stringResource(R.string.group_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
}
