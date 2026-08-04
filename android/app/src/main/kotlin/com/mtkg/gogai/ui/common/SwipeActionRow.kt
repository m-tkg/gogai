package com.mtkg.gogai.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/// スワイプで表示するアクション1件分の定義（iOS の `.swipeActions` 内ボタン相当）。
data class SwipeAction(
    val icon: ImageVector,
    val label: String,
    val color: Color,
    val onClick: () -> Unit,
)

private val ActionRevealWidth = 88.dp

/// iOS の `.swipeActions(edge:allowsFullSwipe:)` 相当を自作した行コンテナ。
/// - leading（右ドラッグ）: 部分リビールでアクションボタンを表示しタップで発火。
///   [allowsLeadingFullSwipe] が true なら、行幅の半分を超えるフルスワイプで自動確定する。
/// - trailing（左ドラッグ）: 部分リビールのみ（フルスワイプ確定なし）。
///
/// AnchoredDraggableState ではなく Animatable + pointerInput による手動実装にしている。
/// （AnchoredDraggableState のコンストラクタ引数は Compose Foundation のバージョンによって
/// 変動が大きく、本プロジェクトが依存する 1.8.2 での正確なシグネチャ確認コストを避けるため）
@Composable
fun SwipeActionRow(
    modifier: Modifier = Modifier,
    leading: SwipeAction? = null,
    trailing: SwipeAction? = null,
    allowsLeadingFullSwipe: Boolean = true,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val actionWidthPx = with(density) { ActionRevealWidth.toPx() }
    var rowWidthPx by remember { mutableFloatStateOf(0f) }
    val offsetX = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()

    fun animateTo(target: Float, durationMs: Int = 200) {
        scope.launch { offsetX.animateTo(target, tween(durationMs)) }
    }

    Box(modifier = modifier.onSizeChanged { rowWidthPx = it.width.toFloat() }) {
        // 背面レイヤー: ドラッグで露出するアクションボタン
        Row(modifier = Modifier.fillMaxHeight()) {
            if (leading != null) {
                val revealedPx = offsetX.value.coerceAtLeast(0f)
                if (revealedPx > 0f) {
                    SwipeActionBackground(
                        action = leading,
                        widthPx = revealedPx,
                        onClick = { leading.onClick(); animateTo(0f) },
                    )
                }
            }
            Spacer(modifier = Modifier.weight(1f))
            if (trailing != null) {
                val revealedPx = (-offsetX.value).coerceAtLeast(0f)
                if (revealedPx > 0f) {
                    SwipeActionBackground(
                        action = trailing,
                        widthPx = revealedPx,
                        onClick = { trailing.onClick(); animateTo(0f) },
                    )
                }
            }
        }

        // 前面レイヤー: 実際の行内容。水平ドラッグでオフセットする
        Box(
            modifier = Modifier
                .offset { IntOffset(offsetX.value.roundToInt(), 0) }
                .pointerInput(leading, trailing, allowsLeadingFullSwipe) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            val current = offsetX.value
                            val fullSwipeThreshold = rowWidthPx * 0.5f
                            when {
                                leading != null && allowsLeadingFullSwipe && rowWidthPx > 0f && current >= fullSwipeThreshold -> {
                                    scope.launch {
                                        offsetX.animateTo(rowWidthPx, tween(150))
                                        leading.onClick()
                                        offsetX.snapTo(0f)
                                    }
                                }
                                leading != null && current >= actionWidthPx / 2f -> animateTo(actionWidthPx)
                                trailing != null && current <= -actionWidthPx / 2f -> animateTo(-actionWidthPx)
                                else -> animateTo(0f)
                            }
                        },
                        onDragCancel = { animateTo(0f) },
                        onHorizontalDrag = { change, dragAmount ->
                            change.consume()
                            val minX = if (trailing != null) -actionWidthPx else 0f
                            val maxX = when {
                                leading == null -> 0f
                                allowsLeadingFullSwipe -> rowWidthPx.coerceAtLeast(actionWidthPx)
                                else -> actionWidthPx
                            }
                            val next = (offsetX.value + dragAmount).coerceIn(minX, maxX)
                            scope.launch { offsetX.snapTo(next) }
                        },
                    )
                },
        ) {
            content()
        }
    }
}

@Composable
private fun SwipeActionBackground(action: SwipeAction, widthPx: Float, onClick: () -> Unit) {
    val density = LocalDensity.current
    Box(
        modifier = Modifier
            .fillMaxHeight()
            .width(with(density) { widthPx.toDp() })
            .background(action.color)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(action.icon, contentDescription = action.label, tint = Color.White)
            Text(action.label, color = Color.White, style = MaterialTheme.typography.labelSmall)
        }
    }
}
