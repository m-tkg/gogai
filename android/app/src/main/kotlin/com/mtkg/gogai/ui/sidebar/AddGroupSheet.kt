package com.mtkg.gogai.ui.sidebar

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.mtkg.gogai.R
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.ui.common.FormSheetDialog

/// グループ追加フォーム（iOS AddGroupView の移植）。
@Composable
fun AddGroupSheet(
    groupStore: GroupStore,
    onDismiss: () -> Unit,
) {
    var groupName by remember { mutableStateOf("") }

    FormSheetDialog(
        title = stringResource(R.string.add_group_title),
        confirmLabel = stringResource(R.string.add),
        confirmEnabled = groupName.trim().isNotEmpty(),
        onDismiss = onDismiss,
        onSubmit = {
            groupStore.createGroup(groupName.trim())
        },
    ) {
        Column {
            Text(
                text = stringResource(R.string.add_group_name_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = groupName,
                onValueChange = { groupName = it },
                placeholder = { Text(stringResource(R.string.add_group_name_placeholder)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
