package com.mtkg.gogai.ui.ai

import androidx.compose.runtime.staticCompositionLocalOf
import com.mtkg.gogai.di.AppContainer

/**
 * AppContainer を Compose ツリーに供給する CompositionLocal。
 *
 * Phase 5 の並行作業制約により app/GogaiNavHost.kt を編集できないため、既存の各画面呼び出し
 * （ArticleDetailScreen 等）に AppContainer/TextGenerating を新しい必須引数として追加できない。
 * その代わりに MainActivity.kt で最上位から provide し、AI 機能を持つ画面側は
 * `LocalAppContainer.current` 経由で `aiAvailable()`/`currentTextGenerator()` を参照する。
 * NavHost 側のコード変更は一切不要になる。
 */
val LocalAppContainer = staticCompositionLocalOf<AppContainer?> { null }
