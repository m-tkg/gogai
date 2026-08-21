package com.mtkg.gogai.ai

import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS SentenceSplitterTests と同じケース(両プラットフォームで分割結果が一致することが前提) */
class SentenceSplitterTest {

    @Test
    fun `和文は句点で分割し句点と後続の空白は前の文に付く`() {
        assertEquals(
            listOf("朝7時に起きました。", "朝ご飯を食べた。 ", "調子が悪かった。"),
            SentenceSplitter.split("朝7時に起きました。朝ご飯を食べた。 調子が悪かった。"),
        )
    }

    @Test
    fun `和文の閉じ括弧は前の文に含める`() {
        assertEquals(
            listOf("彼は「行く。」", "と言った。", "本当か？」", "と返した。"),
            SentenceSplitter.split("彼は「行く。」と言った。本当か？」と返した。"),
        )
    }

    @Test
    fun `欧文はピリオドと空白の後に大文字が続く位置で分割する`() {
        assertEquals(
            listOf("I had breakfast. ", "It was good! ", "Really? ", "Yes."),
            SentenceSplitter.split("I had breakfast. It was good! Really? Yes."),
        )
    }

    @Test
    fun `欧文のピリオドの後が小文字なら分割しない`() {
        assertEquals(
            listOf("See the docs e.g. the guide. ", "Then go."),
            SentenceSplitter.split("See the docs e.g. the guide. Then go."),
        )
    }

    @Test
    fun `省略形やイニシャルの後では分割しない`() {
        assertEquals(listOf("Dr. Smith arrived. ", "He sat."), SentenceSplitter.split("Dr. Smith arrived. He sat."))
        assertEquals(listOf("J. K. Rowling wrote it. ", "Read it."), SentenceSplitter.split("J. K. Rowling wrote it. Read it."))
        assertEquals(listOf("The U.S. government acted. ", "It worked."), SentenceSplitter.split("The U.S. government acted. It worked."))
    }

    @Test
    fun `閉じ引用符の後で分割する`() {
        assertEquals(
            listOf("He said \"Go.\" ", "She left. ", "“Why?” ", "Nobody knew."),
            SentenceSplitter.split("He said \"Go.\" She left. “Why?” Nobody knew."),
        )
    }

    @Test
    fun `小数点や数字の途中では分割しない`() {
        assertEquals(listOf("Version 3.5 is out. ", "Get it."), SentenceSplitter.split("Version 3.5 is out. Get it."))
    }

    @Test
    fun `文末記号がなければ全体を1文にする`() {
        assertEquals(listOf("Home"), SentenceSplitter.split("Home"))
        assertEquals(listOf("  見出し  "), SentenceSplitter.split("  見出し  "))
    }

    @Test
    fun `末尾の句点では分割しない`() {
        assertEquals(listOf("終わり。"), SentenceSplitter.split("終わり。"))
        assertEquals(listOf("Done. "), SentenceSplitter.split("Done. "))
    }

    @Test
    fun `空文字は空リスト`() {
        assertEquals(emptyList<String>(), SentenceSplitter.split(""))
    }

    @Test
    fun `分割結果を連結すると元の文字列に一致する`() {
        val samples = listOf(
            "  Leading space. Then 改行\n続く。最後 ",
            "Mixed 日本語 and English. 日本語の文。Next one!  Yes?\tTab.",
            "No terminal punctuation at all",
            "...ellipsis... then more... And More.",
        )
        for (sample in samples) {
            assertEquals("可逆でなければならない: $sample", sample, SentenceSplitter.split(sample).joinToString(""))
        }
    }

    @Test
    fun `1文だけの入力は再分割しても同じ1文になる`() {
        for (piece in SentenceSplitter.split("I had breakfast. It was good! 朝ご飯。おいしかった。")) {
            assertEquals(listOf(piece), SentenceSplitter.split(piece))
        }
    }
}
