package com.mtkg.gogai.ai

import com.mtkg.gogai.network.fetchStringResponse
import java.io.IOException
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * 記事 URL から本文テキストを取得する（iOS ArticleContentFetcher, AI/ArticleContentFetcher.swift の移植）。
 * ページ内ブラウザ（CustomTabs 等）は表示中ページのテキストを取得できないため、
 * AI に渡す本文はアプリが記事 URL を直接フェッチして抽出する。
 */
object ArticleContentFetcher {
    /** これ未満の実テキストしか持たない <article>/<main> は本文とみなさない下限文字数。 */
    private const val MIN_MAIN_CONTENT_TEXT_LENGTH = 200

    private val tagRegex = Regex("<[^>]+>")
    private val numericEntityRegex = Regex("&#x?[0-9a-fA-F]+;", RegexOption.IGNORE_CASE)
    private val whitespaceRegex = Regex("[ \\t]+")

    // Swift 版の Dictionary リテラルと同じ列挙順（置換対象は互いに素なので順序自体は結果に影響しない）
    private val entityTable = linkedMapOf(
        "&amp;" to "&", "&lt;" to "<", "&gt;" to ">", "&quot;" to "\"", "&#39;" to "'", "&apos;" to "'",
        "&nbsp;" to " ", "&rsquo;" to "’", "&lsquo;" to "‘", "&rdquo;" to "”", "&ldquo;" to "“",
        "&hellip;" to "…", "&mldr;" to "…", "&mdash;" to "—", "&ndash;" to "–",
    )

    /** 記事 URL の HTML を取得し、プレーンテキストを返す */
    suspend fun fetchPlainText(url: String, httpClient: OkHttpClient = OkHttpClient()): String {
        val request = Request.Builder().url(url).get().build()
        val (code, html) = httpClient.fetchStringResponse(request)
        if (code >= 400) throw IOException("HTTP $code from $url")
        return extractText(html)
    }

    /**
     * HTML からプレーンテキストを抽出する。
     * script / style / noscript / head は中身ごと除去してからタグを剥がす。
     * <article>/<main> があればナビゲーション・フッター等を除いた本文だけを使う。
     */
    fun extractText(html: String): String {
        var text = html
        for (tag in listOf("script", "style", "noscript", "head")) {
            val regex = Regex("<$tag[^>]*>[\\s\\S]*?</$tag>", RegexOption.IGNORE_CASE)
            text = regex.replace(text, " ")
        }
        extractMainContent(text)?.let { text = it }
        return stripHTML(text)
    }

    /**
     * HTML タグ・主要エンティティ・数値文字参照を除去してプレーンテキスト化する。
     * ストック要約・記事要約プロンプト整形の両方から呼ばれる、本来 HTML 抽出の責務を持つこちら側が所有する。
     */
    fun stripHTML(html: String): String {
        var text = tagRegex.replace(html, " ")
        for ((entity, char) in entityTable) {
            text = text.replace(entity, char)
        }
        text = decodeNumericEntities(text)
        return whitespaceRegex.replace(text, " ").trim()
    }

    /**
     * 数値文字参照(&#NNN; / &#xHHHH;)をデコードする。アイコンフォント用の私用領域
     * (Private Use Area)コードポイントはテキストとして意味を持たないため空文字にする。
     */
    private fun decodeNumericEntities(text: String): String {
        return numericEntityRegex.replace(text) { match ->
            val token = match.value
            val inner = token.substring(2, token.length - 1) // "&#" 接頭辞と ";" 接尾辞を除去
            val isHex = inner.startsWith("x", ignoreCase = true)
            val digits = if (isHex) inner.substring(1) else inner
            val value = digits.toLongOrNull(if (isHex) 16 else 10) ?: return@replace ""
            if (!isValidScalar(value) || isPrivateUse(value)) "" else codePointToString(value)
        }
    }

    private fun isValidScalar(value: Long): Boolean =
        value in 0..0x10FFFF && value !in 0xD800..0xDFFF // サロゲート単体は不正なスカラー値（Swift の Unicode.Scalar も nil）

    private fun codePointToString(value: Long): String = String(Character.toChars(value.toInt()))

    private fun isPrivateUse(value: Long): Boolean =
        value in 0xE000..0xF8FF || value in 0xF0000..0xFFFFD || value in 0x100000..0x10FFFD

    /**
     * <article> または <main> で囲われた本文があればその中身を返す。
     * ナビゲーションバーやフッターがそのまま本文に混入して要約品質が落ちるのを防ぐ。
     * 該当箇所が複数ある場合は実テキストが最も多いものを採用し、実テキストが少ない
     * (=関連記事カード等の可能性が高い)場合は null を返して呼び出し元にページ全体へフォールバックさせる。
     *
     * 判定は HTML バイト長ではなく stripHTML 後の実テキスト長で行う。
     */
    private fun extractMainContent(html: String): String? {
        for (tag in listOf("article", "main")) {
            val regex = Regex("<$tag[^>]*>([\\s\\S]*?)</$tag>", RegexOption.IGNORE_CASE)
            val best = regex.findAll(html)
                .mapNotNull { match -> match.groupValues.getOrNull(1) }
                .map { inner -> inner to stripHTML(inner).length }
                .maxByOrNull { it.second }
            if (best != null && best.second >= MIN_MAIN_CONTENT_TEXT_LENGTH) {
                return best.first
            }
        }
        return null
    }
}
