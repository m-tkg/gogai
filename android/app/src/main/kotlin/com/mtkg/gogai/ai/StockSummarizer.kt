package com.mtkg.gogai.ai

import okhttp3.OkHttpClient

/**
 * ストックした記事を5セクション構成(何についての記事か/何の目的で書かれたか/
 * 筆者が一番伝えたいこと/20行以内の要約/この記事から得られる学び)で日本語要約する
 * （iOS StockSummarizer, AI/StockSummarizer.swift の移植）。
 *
 * Gogai Android は AI をリモート API（OpenAI/Gemini/Claude）のみで提供する方針のため、
 * iOS 版がオンデバイスモデルのトークン制限向けに持っていた map-reduce のチャンク処理
 * (condense/chunk/セクション個別生成によるフォールバック)は移植しない。
 * ここでは iOS 版の「generator is RemoteAITextGenerator」分岐が常に真である場合の挙動、
 * つまりリモート AI 経路のみを実装する。
 */
class StockSummarizer(
    private val generator: TextGenerating,
    private val providerLabel: String = "AI",
    private val progress: ((String) -> Unit)? = null,
) {
    /** 記事 URL から本文を取得してサマリーを生成する */
    suspend fun summarize(url: String, title: String?, httpClient: OkHttpClient = OkHttpClient()): String {
        log("記事本文を取得中: ${hostOf(url)}")
        val text = ArticleContentFetcher.fetchPlainText(url, httpClient)
        log("記事本文の取得完了: ${text.length}文字")
        return summarize(title, text)
    }

    /** 取得済みの本文からサマリーを生成する(テスト用に URL 取得と分離) */
    suspend fun summarize(title: String?, text: String): String {
        log("本文を要約用に整形中")
        val cleanTitle = (title ?: "").trim()
        val cleanText = ArticleContentFetcher.stripHTML(text)
        if (cleanTitle.isEmpty() && cleanText.isEmpty()) throw AiError.EmptyContent
        log("整形後の本文: ${cleanText.length}文字")

        if (cleanText.length <= NO_SUMMARY_NEEDED_TEXT_LIMIT) {
            log("本文が${NO_SUMMARY_NEEDED_TEXT_LIMIT}文字以下のため、AI要約をスキップ")
            val body = cleanText.ifEmpty { cleanTitle }
            return assembleSections(
                topic = SECTION_PLACEHOLDER,
                purpose = SECTION_PLACEHOLDER,
                mainMessage = SECTION_PLACEHOLDER,
                summaryLines = listOf(
                    "内容が少ないため、要約せず本文をそのまま表示します。",
                    body,
                ),
                learningLines = emptyList(),
            )
        }

        var sourceText = cleanText
        if (cleanText.length > REMOTE_MAX_PROMPT_LENGTH) {
            sourceText = cleanText.take(REMOTE_MAX_PROMPT_LENGTH)
            log("外部AI向けに本文を${sourceText.length}文字へ短縮")
        }

        val prompt = listOf(cleanTitle, sourceText).filter { it.isNotEmpty() }.joinToString("\n\n")

        // 通常経路: 1回の生成で4セクションをまとめて作らせる。parse できればそのまま採用。
        log("${providerLabel}へ要約リクエスト送信中")
        val combined = enforceSummaryLineLimit(generator.generate(FINAL_INSTRUCTIONS, prompt))
        log("${providerLabel}から要約レスポンスを受信")

        val parsed = StockSummary.parse(combined)
        if (parsed != null) {
            log("要約レスポンスの解析に成功")
            // 外部 AI では rate limit を避けるため、学びが欠けていても追加リクエストしない。
            return combined
        }

        // 外部 AI では rate limit を避けるため、セクションごとの追加生成は行わない。
        // 1回目の出力を「要約」本文として採用し、固定見出しはこちら側で補う。
        log("レスポンス形式が不完全なため、追加リクエストなしで見出しを補完")
        return assembleSections(
            topic = SECTION_PLACEHOLDER,
            purpose = SECTION_PLACEHOLDER,
            mainMessage = SECTION_PLACEHOLDER,
            summaryLines = sectionLines(combined).take(SUMMARY_LINE_LIMIT),
            learningLines = emptyList(),
        )
    }

    private fun log(message: String) {
        progress?.invoke(message)
    }

    companion object {
        /**
         * 外部 AI 向けプロンプトに渡す本文の上限文字数。
         * 外部 AI はオンデバイスよりコンテキストが大きく、API rate limit の方が問題になりやすい。
         * map-reduce で複数リクエストに分割せず、1回の要約に寄せるための上限。
         */
        const val REMOTE_MAX_PROMPT_LENGTH = 20_000

        /** 「要約」セクションの最大行数 */
        const val SUMMARY_LINE_LIMIT = 20

        /** 本文がこれ以下ならAI要約せず、そのまま要約欄に表示する。 */
        const val NO_SUMMARY_NEEDED_TEXT_LIMIT = 100

        /**
         * セクション個別生成でも中身が得られなかったときに埋めるプレースホルダ。
         * これを入れることで4見出し(学びを除く)すべてが非空になり StockSummary.parse() が必ず成功する
         * (=表示側が固定見出しレイアウト・見出しの色付けを常に行える)。
         */
        const val SECTION_PLACEHOLDER = "（生成できませんでした）"

        private fun hostOf(url: String): String =
            runCatching { java.net.URI(url).host }.getOrNull() ?: url

        /**
         * モデル出力から見出し行(先頭が #)と空行を除いた本文行の配列を返す。
         * モデルがセクション本文に見出しをエコーバックしても最終出力の構造を壊さないため。
         */
        fun sectionLines(text: String): List<String> =
            text.split("\n").map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }

        /**
         * 各セクション本文を固定見出しに差し込んで最終テキストを組み立てる。
         * 空セクションは sectionPlaceholder で埋め、4見出し(学びを除く)すべてが非空になるようにする
         * (StockSummary.parse() が必ず成功する)。学びは生成できなければプレースホルダで埋める。
         */
        fun assembleSections(
            topic: String,
            purpose: String,
            mainMessage: String,
            summaryLines: List<String>,
            learningLines: List<String>,
        ): String {
            fun filled(body: String) = body.ifEmpty { SECTION_PLACEHOLDER }
            val summaryBody = if (summaryLines.isEmpty()) SECTION_PLACEHOLDER else summaryLines.joinToString("\n")
            val learningBody = if (learningLines.isEmpty()) SECTION_PLACEHOLDER else learningLines.joinToString("\n")
            return listOf(
                "## 何についての記事か",
                filled(topic),
                "",
                "## 何の目的で書かれたか",
                filled(purpose),
                "",
                "## 筆者が一番伝えたいこと",
                filled(mainMessage),
                "",
                "## 要約(20行以内)",
                summaryBody,
                "",
                "## この記事から得られる学び",
                learningBody,
            ).joinToString("\n")
        }

        /**
         * 「## 要約」セクションの本文を summaryLineLimit 行までに機械的に切り詰める。
         * プロンプト指示だけでは 20 行を超える出力がありうるためハードに保証する。
         * 要約の後に続くセクション(学びなど、次の "##" 見出し以降)は切り詰め対象外として保持する。
         */
        fun enforceSummaryLineLimit(text: String, limit: Int = SUMMARY_LINE_LIMIT): String {
            val headingIndex = text.indexOf("## 要約")
            if (headingIndex < 0) return text
            val head = text.substring(0, headingIndex)
            val lines = text.substring(headingIndex).split("\n").toMutableList()
            if (lines.isEmpty()) return text
            val heading = lines.removeAt(0)
            val nextHeadingIndex = lines.indexOfFirst { it.trim().startsWith("##") }
            val body = if (nextHeadingIndex >= 0) lines.subList(0, nextHeadingIndex) else lines
            val rest = if (nextHeadingIndex >= 0) lines.subList(nextHeadingIndex, lines.size) else emptyList()
            val combined = listOf(heading) + body.take(limit) + rest
            return head + combined.joinToString("\n")
        }

        val FINAL_INSTRUCTIONS: String = listOf(
            "あなたは記事要約アシスタントです。与えられた記事を必ず日本語で要約してください。",
            "出力は以下の見出しのみで構成し、見出し以外の文章(前置き・後書き)を追加しないでください。",
            "",
            "## 何についての記事か",
            "## 何の目的で書かれたか",
            "## 筆者が一番伝えたいこと",
            "## 要約(20行以内)",
            "## この記事から得られる学び",
        ).joinToString("\n")
    }
}
