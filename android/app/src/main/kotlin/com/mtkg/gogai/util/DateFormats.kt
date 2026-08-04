package com.mtkg.gogai.util

import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.DateTimeParseException
import java.time.format.FormatStyle
import java.util.Locale

/**
 * iOS の Utilities/DateFormatter+.swift 相当。バックエンド API が返す日時文字列を
 * Instant にパースするための 3 フォーマット定義。
 *
 * オフセットは appendOffsetId() で表現しており、パース時は "Z" と "+09:00"（コロン付き）/
 * "+0900"（コロンなし）のいずれの表記も受け付ける（java.time の OffsetIdPrinterParser は
 * パース時に寛容な実装になっているため、iOS の DateFormatter における "Z" パターン相当の
 * 挙動をコロン付きオフセットにも拡張して受け入れる）。
 */
object DateFormats {
    /** "yyyy-MM-dd'T'HH:mm:ss.SSSZ" 相当（ミリ秒あり） */
    val iso8601Full: DateTimeFormatter = DateTimeFormatterBuilder()
        .appendPattern("yyyy-MM-dd'T'HH:mm:ss.SSS")
        .appendOffsetId()
        .toFormatter(Locale.US)

    /** "yyyy-MM-dd'T'HH:mm:ssZ" 相当（ミリ秒なし） */
    val iso8601: DateTimeFormatter = DateTimeFormatterBuilder()
        .appendPattern("yyyy-MM-dd'T'HH:mm:ss")
        .appendOffsetId()
        .toFormatter(Locale.US)

    /** SQLite の datetime('now') が返す "YYYY-MM-DD HH:MM:SS"（UTC）形式 */
    val sqliteDateTime: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.US)
}

/**
 * iOS の String.parsedDate と同じ順序で 3 フォーマットを順に試し、最初に成功した結果を返す。
 * いずれのフォーマットにも一致しない場合は null。
 */
fun String.parsedDate(): Instant? {
    try {
        return OffsetDateTime.parse(this, DateFormats.iso8601Full).toInstant()
    } catch (_: DateTimeParseException) {
        // 次のフォーマットを試す
    }
    try {
        return OffsetDateTime.parse(this, DateFormats.iso8601).toInstant()
    } catch (_: DateTimeParseException) {
        // 次のフォーマットを試す
    }
    try {
        return LocalDateTime.parse(this, DateFormats.sqliteDateTime).toInstant(ZoneOffset.UTC)
    } catch (_: DateTimeParseException) {
        // どのフォーマットにも一致しなかった
    }
    return null
}

/**
 * iOS の String.displayDate と同じく、パースに成功すれば端末ロケール・端末タイムゾーンの
 * medium 日付 + short 時刻表記を返す。パースに失敗した場合は元の文字列をそのまま返す。
 */
fun String.displayDate(): String {
    val instant = parsedDate() ?: return this
    val formatter = DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
    return formatter.format(instant)
}
