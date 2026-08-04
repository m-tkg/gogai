package com.mtkg.gogai.ui.sidebar

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.unit.dp
import com.mtkg.gogai.R
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.FieldUpdate
import com.mtkg.gogai.store.FeedStore
import com.mtkg.gogai.store.GroupStore
import com.mtkg.gogai.ui.common.FormSheetDialog
import com.mtkg.gogai.ui.common.GroupPickerSection

/// フィード編集フォーム（iOS EditFeedView の移植）。タイトルとグループ変更を扱う。
@Composable
fun EditFeedSheet(
    feed: Feed,
    feedStore: FeedStore,
    groupStore: GroupStore,
    onDismiss: () -> Unit,
) {
    var titleText by remember { mutableStateOf(feed.title.orEmpty()) }
    var selectedGroupId by remember { mutableStateOf(feed.group_id) }
    val groups by groupStore.groups.collectAsState()

    FormSheetDialog(
        title = stringResource(R.string.edit_feed_title),
        confirmLabel = stringResource(R.string.save),
        onDismiss = onDismiss,
        onSubmit = {
            val newTitle = titleText.trim()
            val groupUpdate = selectedGroupId?.let { FieldUpdate.Set(it) } ?: FieldUpdate.Clear
            feedStore.updateFeed(
                id = feed.id,
                title = newTitle.ifEmpty { null },
                groupId = groupUpdate,
            )
        },
    ) {
        Column {
            Text(
                text = stringResource(R.string.edit_feed_title_section),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = titleText,
                onValueChange = { titleText = it },
                placeholder = { Text(stringResource(R.string.edit_feed_title_placeholder)) },
                singleLine = true,
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
