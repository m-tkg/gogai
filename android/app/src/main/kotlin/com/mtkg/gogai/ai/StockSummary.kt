package com.mtkg.gogai.ai

/**
 * StockSummarizer が生成した固定見出しテキストをセクションごとに分割した表示用モデル
 * （iOS StockSummary, AI/StockSummary.swift の移植）。
 * サーバーには見出し付きプレーンテキストのまま保存し、表示側でこのパーサを通す。
 */
data class StockSummary(
    val topic: String,
    val purpose: String,
    val mainMessage: String,
    val summaryLines: List<String>,
    /**
     * 「この記事から得られる学び」セクション。旧保存済みの4セクション形式にはこのセクションがないため、
     * 見出し自体がない・本文が空の場合は null にする
     * (表示側は null なら学び見出しごと非表示にし、旧データの構造化表示を維持する)。
     */
    val learningLines: List<String>?,
) {
    companion object {
        /**
         * 4セクション(何についての記事か/何の目的で書かれたか/筆者が一番伝えたいこと/要約)が
         * 1つでも欠けている、または中身が空なら null を返す(呼び出し側は生テキスト表示にフォールバックする)。
         * 学びセクションは optional 扱いのため、この判定には含めない。
         */
        fun parse(text: String): StockSummary? {
            val sections = splitSections(text)
            val topic = sections["何についての記事か"]?.takeIf { it.isNotEmpty() } ?: return null
            val purpose = sections["何の目的で書かれたか"]?.takeIf { it.isNotEmpty() } ?: return null
            val mainMessage = sections["筆者が一番伝えたいこと"]?.takeIf { it.isNotEmpty() } ?: return null
            val summaryBody = sections["要約"]?.takeIf { it.isNotEmpty() } ?: return null

            val learningLines = sections["学び"]?.let { bodyLines(it) }
            return StockSummary(
                topic = topic,
                purpose = purpose,
                mainMessage = mainMessage,
                summaryLines = bodyLines(summaryBody),
                learningLines = if (learningLines.isNullOrEmpty()) null else learningLines,
            )
        }

        private fun bodyLines(body: String): List<String> =
            body.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        /**
         * "## 見出し" 区切りでセクション本文を集める。「要約(20行以内)」のような
         * 補足付き見出しも "要約" を含んでいれば "要約" キーとして扱う。
         */
        private fun splitSections(text: String): Map<String, String> {
            val result = mutableMapOf<String, String>()
            var currentKey: String? = null
            var currentBody = mutableListOf<String>()

            fun flush() {
                val key = currentKey ?: return
                result[key] = currentBody.joinToString("\n").trim()
            }

            for (line in text.split("\n")) {
                val trimmed = line.trim()
                if (trimmed.startsWith("##")) {
                    flush()
                    val heading = trimmed.trimStart('#').trim()
                    currentKey = normalizedKey(heading)
                    currentBody = mutableListOf()
                } else {
                    currentBody.add(line)
                }
            }
            flush()
            return result
        }

        private fun normalizedKey(heading: String): String {
            if (heading.contains("要約")) return "要約"
            if (heading.contains("学び")) return "学び"
            return heading
        }
    }
}
