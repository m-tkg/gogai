package com.mtkg.gogai.util

import kotlin.math.abs

/**
 * 横スワイプの方向と成立判定（純関数）。
 * ios/Gogai/Utilities/HorizontalSwipe.swift の閾値ロジック相当。
 * 「横に80pt超 かつ 縦成分が横成分の半分未満（スクロールと区別）」で成立する。
 *
 * Compose の Modifier 拡張（ジェスチャ検出そのもの）は Phase 3 で別途実装する。
 * ここでは判定ロジックのみを純関数として提供する。
 */
enum class HorizontalSwipeDirection {
    Left,
    Right,
}

const val MIN_DISTANCE = 80f

fun matchHorizontalSwipe(dx: Float, dy: Float): HorizontalSwipeDirection? {
    if (abs(dx) <= MIN_DISTANCE) return null
    if (abs(dy) >= abs(dx) * 0.5f) return null
    return if (dx < 0) HorizontalSwipeDirection.Left else HorizontalSwipeDirection.Right
}
