package com.mtkg.gogai.ui.sidebar

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.store.FeedStore
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.ui.common.FormSheetDialog
import com.mtkg.gogai.ui.common.GroupPickerSection

/// フィード追加フォーム（iOS AddFeedView の移植）。
@Composable
fun AddFeedSheet(
    feedStore: FeedStore,
    groupStore: GroupStore,
    onDismiss: () -> Unit,
) {
    var urlText by remember { mutableStateOf("") }
    var selectedGroupId by remember { mutableStateOf<Int?>(null) }
    val groups by groupStore.groups.collectAsState()

    FormSheetDialog(
        title = stringResource(R.string.add_feed_title),
        confirmLabel = stringResource(R.string.add),
        confirmEnabled = urlText.trim().isNotEmpty(),
        onDismiss = onDismiss,
        onSubmit = {
            feedStore.createFeed(url = urlText.trim(), groupId = selectedGroupId)
        },
    ) {
        Column {
            Text(
                text = stringResource(R.string.add_feed_url_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = urlText,
                onValueChange = { urlText = it },
                placeholder = { Text(stringResource(R.string.add_feed_url_placeholder)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        GroupPickerSection(
            groups = groups,
            selectedGroupId = selectedGroupId,
            onSelect = { selectedGroupId = it },
        )
    }
}
