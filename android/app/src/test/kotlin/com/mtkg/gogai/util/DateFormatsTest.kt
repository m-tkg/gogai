package com.mtkg.gogai.util

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DateFormatsTest {
    @Test
    fun `SQLite 形式は UTC として解釈される`() {
        val instant = "2026-01-02 03:04:05".parsedDate()
        assertEquals(Instant.parse("2026-01-02T03:04:05Z"), instant)
    }

    @Test
    fun `ISO Z 付き(ミリ秒なし)をパースできる`() {
        val instant = "2026-01-02T03:04:05Z".parsedDate()
        assertEquals(Instant.parse("2026-01-02T03:04:05Z"), instant)
    }

    @Test
    fun `ISO Z 付き(小数秒あり)をパースできる`() {
        val instant = "2026-01-02T03:04:05.123Z".parsedDate()
        assertEquals(Instant.parse("2026-01-02T03:04:05.123Z"), instant)
    }

    @Test
    fun `プラスオフセット(コロン付き)をパースできる`() {
        val instant = "2026-01-02T12:04:05+09:00".parsedDate()
        assertEquals(Instant.parse("2026-01-02T03:04:05Z"), instant)
    }

    @Test
    fun `プラスオフセット(コロン付き、小数秒あり)をパースできる`() {
        val instant = "2026-01-02T12:04:05.500+09:00".parsedDate()
        assertEquals(Instant.parse("2026-01-02T03:04:05.500Z"), instant)
    }

    @Test
    fun `パース不能文字列は null を返す`() {
        assertNull("not a date".parsedDate())
    }

    @Test
    fun `displayDate はパース成功時に空でない表示文字列を返す`() {
        val display = "2026-01-02T03:04:05Z".displayDate()
        assert(display.isNotBlank()) { "displayDate は空でない文字列を返すべき" }
        assert(display != "2026-01-02T03:04:05Z") { "displayDate は raw と異なる整形済み文字列を返すべき" }
    }

    @Test
    fun `displayDate はパース不能な場合 raw 文字列をそのまま返す`() {
        val raw = "not a date"
        assertEquals(raw, raw.displayDate())
    }
}
