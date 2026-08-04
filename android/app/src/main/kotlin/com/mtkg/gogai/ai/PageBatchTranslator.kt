package com.mtkg.gogai.ai

/**
 * 文書順のテキストノードをバッチにまとめて翻訳する（iOS FMPageTranslator, AI/FMPageTranslator.swift の移植）。
 * ノード単体を独立して翻訳すると文脈が失われるため、文書順の連続ノードを1バッチにまとめ、
 * id タグ付きで一括翻訳することで文脈を保つ。
 * UI・WebView・キャッシュに依存しない純粋なロジックのみを持つ(テスト容易性のため)。
 */
class PageBatchTranslator(private val generator: TextGenerating) {

    data class Segment(val index: Int, val text: String)

    /**
     * texts(文書順の全ノード)のうち indicesToTranslate を日本語へ翻訳する。
     * バッチ翻訳が失敗、または応答に id が欠落したノードは単体で個別リトライする。
     * 個別リトライにも失敗したノードは戻り値に含まれない(呼び出し側は原文のまま表示する)。
     */
    /**
     * [onProgress] は完了(成功/失敗いずれも確定)したセグメント数が変わるたびに (完了数, 総数) で呼ばれる。
     * UI の進捗表示（「翻訳中… (n/m)」）用のオプション引数で、省略可能（既定 null は何もしない）。
     */
    suspend fun translate(
        texts: List<String>,
        indicesToTranslate: List<Int>,
        pageTitle: String,
        onProgress: ((completed: Int, total: Int) -> Unit)? = null,
    ): Map<Int, String> {
        if (indicesToTranslate.isEmpty()) return emptyMap()
        val segments = indicesToTranslate.map { Segment(it, texts[it]) }
        val total = segments.size
        var completed = 0

        val results = mutableMapOf<Int, String>()
        for (batch in makeBatches(segments, BATCH_CHAR_BUDGET)) {
            val first = batch.firstOrNull() ?: continue
            // バッチ先頭ノードの直前ノードを、翻訳対象にも出力対象にも含めない文脈として渡す
            val contextText = if (first.index > 0) texts[first.index - 1] else null
            runCatching { translateBatch(batch, contextText, pageTitle) }
                .getOrNull()
                ?.let { translated -> for ((index, text) in translated) results[index] = text }
            completed += batch.count { results.containsKey(it.index) }
            onProgress?.invoke(completed, total)

            for (segment in batch) {
                if (results[segment.index] == null) {
                    val translated = runCatching { translateSingle(segment, pageTitle) }.getOrNull()
                    if (translated != null) results[segment.index] = translated
                    // 個別リトライの成否に関わらず、このセグメントの処理は完了したとして数える
                    // (失敗しても原文のまま表示されるだけで、進捗表示は先へ進める)。
                    completed += 1
                    onProgress?.invoke(completed, total)
                }
            }
        }
        return results
    }

    private suspend fun translateBatch(batch: List<Segment>, contextText: String?, pageTitle: String): Map<Int, String> {
        val response = generator.generate(instructions(pageTitle), buildPrompt(batch, contextText))
        return parseResponse(response)
    }

    private suspend fun translateSingle(segment: Segment, pageTitle: String): String {
        val response = generator.generate(instructions(pageTitle), buildPrompt(listOf(segment), null))
        return parseResponse(response)[segment.index] ?: throw AiError.ParseFailed
    }

    companion object {
        /**
         * 1バッチに含める原文の合計文字数の目安。
         * 日本語訳は原文より膨らむため、入出力合計の上限に余裕を持たせて小さめに取る。
         * StockSummarizer の chunk 相当の値より小さいのは意図的な差
         * (こちらは id タグ付きの一括翻訳出力、あちらは要点箇条書きの中間要約出力で、出力の膨らみ方が異なるため)。
         */
        const val BATCH_CHAR_BUDGET = 1800

        private val responseRegex = Regex("⟦(\\d+)⟧")

        /** 連続するセグメントを合計文字数が charBudget を超えない範囲でバッチにまとめる */
        fun makeBatches(segments: List<Segment>, charBudget: Int): List<List<Segment>> {
            val batches = mutableListOf<List<Segment>>()
            var current = mutableListOf<Segment>()
            var currentLength = 0
            for (segment in segments) {
                if (current.isNotEmpty() && currentLength + segment.text.length > charBudget) {
                    batches.add(current)
                    current = mutableListOf()
                    currentLength = 0
                }
                current.add(segment)
                currentLength += segment.text.length
            }
            if (current.isNotEmpty()) batches.add(current)
            return batches
        }

        fun buildPrompt(batch: List<Segment>, contextText: String?): String {
            val lines = mutableListOf<String>()
            if (!contextText.isNullOrEmpty()) lines.add("⟦ctx⟧$contextText")
            for (segment in batch) lines.add("⟦${segment.index}⟧${segment.text}")
            return lines.joinToString("\n")
        }

        fun instructions(pageTitle: String): String = listOf(
            "あなたは翻訳者です。ウェブページ「$pageTitle」の断片を、文脈を保ちながら自然な日本語に翻訳してください。",
            "各行は「⟦id⟧原文」の形式です。同じ id を使って「⟦id⟧訳文」の行だけを、原文と同じ順序で出力してください。",
            "「⟦ctx⟧」で始まる行は文脈把握のための参考情報です。翻訳せず、出力にも含めないでください。",
            "id の追加・削除・順序の変更はしないでください。",
        ).joinToString("\n")

        /**
         * 「⟦id⟧訳文」形式の応答を id → 訳文 の辞書にパースする。
         * 「⟦ctx⟧」など数字でない id は自然に無視される。
         */
        fun parseResponse(response: String): Map<Int, String> {
            val matches = responseRegex.findAll(response).toList()
            val result = mutableMapOf<Int, String>()
            for ((i, match) in matches.withIndex()) {
                val id = match.groupValues[1].toIntOrNull() ?: continue
                val contentStart = match.range.last + 1
                val contentEnd = if (i + 1 < matches.size) matches[i + 1].range.first else response.length
                if (contentEnd < contentStart) continue
                result[id] = response.substring(contentStart, contentEnd).trim()
            }
            return result
        }
    }
}
