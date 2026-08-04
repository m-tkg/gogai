package com.mtkg.gogai.store

import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/// iOS の `ISO8601DateFormatter().string(from: Date())`（デフォルトオプション）と同じ書式
/// （秒精度・小数秒なし・"Z" 付き、例: "2026-08-04T12:34:56Z"）を再現する。
/// Store 側でテスト時に固定値へ差し替えられるよう、呼び出し側は `() -> String` として注入する。
fun isoNowSeconds(): String =
    DateTimeFormatter.ISO_INSTANT.format(Instant.now().truncatedTo(ChronoUnit.SECONDS))
