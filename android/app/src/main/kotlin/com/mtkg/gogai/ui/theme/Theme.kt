package com.mtkg.gogai.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS のアクセントカラー（システム標準 tint 相当）に合わせる
val AccentColor = Color(0xFF007AFF)
val AccentColorDark = Color(0xFF0A84FF)
val SecretOrange = Color(0xFFFF9500)

// 評価の表現色（iOS の .pink / .indigo 相当）
val LikePink = Color(0xFFFF2D55)
val DislikeIndigo = Color(0xFF5856D6)

private val LightColors = lightColorScheme(
    primary = AccentColor,
    secondary = AccentColor,
)

private val DarkColors = darkColorScheme(
    primary = AccentColorDark,
    secondary = AccentColorDark,
)

@Composable
fun GogaiTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
