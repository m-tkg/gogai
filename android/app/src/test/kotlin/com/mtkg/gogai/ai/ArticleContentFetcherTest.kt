package com.mtkg.gogai.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArticleContentFetcherTest {
    @Test
    fun `article タグ内の本文だけを抽出しナビゲーションやフッターは除外する`() {
        val longBody = "本文段落です。".repeat(50) // 200文字超
        val html = """
            <html><body>
            <nav>ホーム | 記事一覧 | お問い合わせ</nav>
            <article><p>$longBody</p></article>
            <footer>Copyright 2026 Gogai</footer>
            </body></html>
        """.trimIndent()

        val text = ArticleContentFetcher.extractText(html)

        assertTrue(text.contains("本文段落です。"))
        assertFalse(text.contains("ホーム"))
        assertFalse(text.contains("Copyright"))
    }

    @Test
    fun `main タグ内の本文だけを抽出できる`() {
        val longBody = "メインコンテンツです。".repeat(50)
        val html = """
            <html><body>
            <aside>サイドバー広告</aside>
            <main><p>$longBody</p></main>
            </body></html>
        """.trimIndent()

        val text = ArticleContentFetcher.extractText(html)

        assertTrue(text.contains("メインコンテンツです。"))
        assertFalse(text.contains("サイドバー広告"))
    }

    @Test
    fun `article の実テキストが200文字未満ならページ全体にフォールバックする`() {
        val html = """
            <html><body>
            <p>ページ全体の本文がここに入ります。これは十分な長さのコンテンツです。</p>
            <article>短い</article>
            </body></html>
        """.trimIndent()

        val text = ArticleContentFetcher.extractText(html)

        // article の中身(短い)ではなく、ページ全体のテキストが使われる
        assertTrue(text.contains("ページ全体の本文がここに入ります"))
    }

    @Test
    fun `script style noscript head は中身ごと除去される`() {
        val html = """
            <html>
            <head><title>タイトル</title></head>
            <body>
            <script>alert('xss')</script>
            <style>.a { color: red; }</style>
            <noscript>JS無効時の文章</noscript>
            <p>本当の本文</p>
            </body></html>
        """.trimIndent()

        val text = ArticleContentFetcher.extractText(html)

        assertTrue(text.contains("本当の本文"))
        assertFalse(text.contains("alert"))
        assertFalse(text.contains("color: red"))
        assertFalse(text.contains("JS無効時の文章"))
        assertFalse(text.contains("タイトル"))
    }

    @Test
    fun `stripHTML はタグとエンティティを除去して空白を圧縮する`() {
        val html = "<p>Tom &amp; Jerry&nbsp;&nbsp;said &quot;hello&quot;</p>"
        val text = ArticleContentFetcher.stripHTML(html)
        assertEquals("Tom & Jerry said \"hello\"", text)
    }

    @Test
    fun `数値文字参照をデコードする`() {
        assertEquals("A", ArticleContentFetcher.stripHTML("&#65;"))
        assertEquals("A", ArticleContentFetcher.stripHTML("&#x41;"))
    }

    @Test
    fun `私用領域の数値文字参照は空文字になる`() {
        // U+E000 は Private Use Area の先頭
        assertEquals("", ArticleContentFetcher.stripHTML("&#xE000;"))
        assertEquals("前後残る", ArticleContentFetcher.stripHTML("前&#xE000;後残る"))
    }
}
