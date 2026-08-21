package com.mtkg.gogai.ai

/**
 * テキストノードの文字列を文単位に分割する(ページ内翻訳の「文単位ミックス」の基礎)。
 * 分割は可逆: 返り値を連結すると必ず元の文字列に一致する(前後の空白は直前の文に付ける)。
 * iOS の `SentenceSplitter.swift` と同一アルゴリズム。文ごとの原文ハッシュをサーバーに保存して
 * 両プラットフォームで共有するため、分割結果が一致しなければならない。
 */
object SentenceSplitter {
    /** 「.」直前の語がこれに含まれる場合は文末とみなさない(省略形)。小文字化して比較する */
    private val abbreviations = setOf(
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "no", "fig",
        "inc", "ltd", "co", "corp", "e.g", "i.e", "cf", "al", "u.s", "u.k", "a.m", "p.m",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    )

    /** 文末候補: 和文終端(句点・感嘆・疑問 + 閉じ括弧 + 任意の空白)/ 欧文終端(. ! ? + 閉じ引用 + 必須の空白) */
    private val boundaryRegex = Regex("[。！？]+[」』）】〕〉》\"'”’)\\]]*\\s*|[.!?]+[\"'”’)\\]]*\\s+")

    /** 欧文終端の直後が「文の始まり」として妥当な文字か(大文字・数字・開き引用/括弧・非ラテン文字) */
    private val sentenceStartRegex = Regex("^[\\p{Lu}\\p{Lt}\\p{Lo}\\p{N}\"“‘'(\\[「『（【]")

    /** 「.」直前の語(英字とピリオドの連続) */
    private val precedingWordRegex = Regex("[A-Za-z.]+$")

    fun split(text: String): List<String> {
        if (text.isEmpty()) return emptyList()
        val pieces = mutableListOf<String>()
        var pieceStart = 0
        for (match in boundaryRegex.findAll(text)) {
            val end = match.range.last + 1
            // 末尾に達した境界は切る必要がない(残りが空になる)
            if (end >= text.length) break
            val punct = text[match.range.first]
            if (isLatinTerminal(punct)) {
                if (!sentenceStartRegex.containsMatchIn(text.substring(end))) continue
                if (punct == '.' && isAbbreviation(text, match.range.first)) continue
            }
            pieces.add(text.substring(pieceStart, end))
            pieceStart = end
        }
        pieces.add(text.substring(pieceStart))
        return pieces
    }

    private fun isLatinTerminal(c: Char): Boolean = c == '.' || c == '!' || c == '?'

    /** 「.」の直前の語が省略形、または 1 文字の大文字(イニシャル)なら文末とみなさない */
    private fun isAbbreviation(text: String, punctIndex: Int): Boolean {
        val head = text.substring(0, punctIndex)
        val word = precedingWordRegex.find(head)?.value ?: return false
        if (word.length == 1 && word.uppercase() == word && word.lowercase() != word) return true
        return abbreviations.contains(word.lowercase())
    }
}
