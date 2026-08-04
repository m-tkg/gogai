package com.mtkg.gogai.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/// フィード・「すべての記事」行に表示する未読数バッジ（iOS UnreadCountBadge の移植）。
/// count が 0 以下のときは何も表示しない。1000 件以上は "1000+"。
@Composable
fun UnreadCountBadge(count: Int, modifier: Modifier = Modifier) {
    if (count <= 0) return
    Text(
        text = if (count >= 1000) "1000+" else count.toString(),
        color = Color.White,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        modifier = modifier
            .background(MaterialTheme.colorScheme.primary, CircleShape)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}
