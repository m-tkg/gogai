package com.mtkg.gogai.ai

/**
 * 記事の日本語要約・日本語翻訳を AI で行うサービス（iOS LocalArticleAI, AI/LocalArticleAI.swift の移植）。
 * Android は AI をリモート API（OpenAI/Gemini/Claude）のみで提供する方針のため、iOS 版の
 * 「ローカル AI」という呼称が意味するオンデバイス性はないが、クラス名・プロンプト文言は原文を保つ。
 * 結果はサーバーに保存しない（iOS と同じく、都度その場で生成するだけの使い捨て）。
 */
class LocalArticleAI(private val generator: TextGenerating) {
    /** 記事を日本語で要約する */
    suspend fun summarize(title: String?, content: String?): String {
        val prompt = preparePrompt(title, content)
        if (prompt.isEmpty()) throw AiError.EmptyContent
        return generator.generate(
            instructions = "あなたは記事要約アシスタントです。与えられた記事を日本語で3〜5文に要約してください。要約の本文のみを出力してください。",
            prompt = prompt,
        )
    }

    /** 記事を日本語に翻訳する */
    suspend fun translateToJapanese(title: String?, content: String?): String {
        val prompt = preparePrompt(title, content)
        if (prompt.isEmpty()) throw AiError.EmptyContent
        return generator.generate(
            instructions = "あなたは翻訳アシスタントです。与えられた記事を自然な日本語に翻訳してください。訳文のみを出力してください。",
            prompt = prompt,
        )
    }

    companion object {
        /**
         * 入出力合計のトークン制限に収まるよう入力テキストをこの文字数で切り詰める
         * （iOS 版の「オンデバイスモデルは入出力合計 4096 トークン」という制約に由来する値を踏襲）。
         */
        const val MAX_PROMPT_LENGTH = 3000

        /**
         * タイトルと本文（HTML/プレーンテキストいずれも可）を AI に渡すプレーンテキストに整形する。
         * HTML タグ・主要エンティティを除去し、コンテキスト上限に収まるよう切り詰める。
         */
        fun preparePrompt(title: String?, content: String?): String {
            val cleanTitle = (title ?: "").trim()
            val cleanBody = ArticleContentFetcher.stripHTML(content ?: "")
            val combined = listOf(cleanTitle, cleanBody).filter { it.isNotEmpty() }.joinToString("\n\n")
            return combined.take(MAX_PROMPT_LENGTH)
        }
    }
}
