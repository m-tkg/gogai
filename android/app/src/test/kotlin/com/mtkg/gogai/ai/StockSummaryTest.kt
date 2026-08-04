package com.mtkg.gogai.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StockSummaryTest {
    private val fiveSectionText = """
        ## 何についての記事か
        記事のトピック説明

        ## 何の目的で書かれたか
        記事の目的説明

        ## 筆者が一番伝えたいこと
        筆者の主張

        ## 要約(20行以内)
        要約行1
        要約行2

        ## この記事から得られる学び
        学び1
        学び2
    """.trimIndent()

    @Test
    fun `5セクションを正しくパースできる`() {
        val summary = StockSummary.parse(fiveSectionText)
        requireNotNull(summary)
        assertEquals("記事のトピック説明", summary.topic)
        assertEquals("記事の目的説明", summary.purpose)
        assertEquals("筆者の主張", summary.mainMessage)
        assertEquals(listOf("要約行1", "要約行2"), summary.summaryLines)
        assertEquals(listOf("学び1", "学び2"), summary.learningLines)
    }

    @Test
    fun `学びセクションが欠けた4セクションのレガシー形式も許容する`() {
        val legacyText = """
            ## 何についての記事か
            記事のトピック説明

            ## 何の目的で書かれたか
            記事の目的説明

            ## 筆者が一番伝えたいこと
            筆者の主張

            ## 要約
            要約行1
        """.trimIndent()

        val summary = StockSummary.parse(legacyText)
        requireNotNull(summary)
        assertNull(summary.learningLines)
    }

    @Test
    fun `必須セクションが1つでも欠けていれば null を返す`() {
        val missingPurpose = """
            ## 何についての記事か
            記事のトピック説明

            ## 筆者が一番伝えたいこと
            筆者の主張

            ## 要約
            要約行1
        """.trimIndent()

        assertNull(StockSummary.parse(missingPurpose))
    }

    @Test
    fun `必須セクションの中身が空なら null を返す`() {
        val emptyTopic = """
            ## 何についての記事か

            ## 何の目的で書かれたか
            記事の目的説明

            ## 筆者が一番伝えたいこと
            筆者の主張

            ## 要約
            要約行1
        """.trimIndent()

        assertNull(StockSummary.parse(emptyTopic))
    }

    @Test
    fun `見出しの補足付き表記も正規化してマッチする`() {
        // 「要約(20行以内)」→「要約」、「この記事から得られる学び」→「学び」
        val summary = StockSummary.parse(fiveSectionText)
        requireNotNull(summary)
        assertEquals(listOf("要約行1", "要約行2"), summary.summaryLines)
        assertEquals(listOf("学び1", "学び2"), summary.learningLines)
    }
}
