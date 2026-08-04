package com.mtkg.gogai.share

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ShareTextParsingTest {
    @Test
    fun `extractSharedUrl はテキスト中の最初のURLを返す`() {
        assertEquals("https://example.com/article", extractSharedUrl("記事です https://example.com/article 面白い"))
    }

    @Test
    fun `extractSharedUrl はURLのみのテキストでも動く`() {
        assertEquals("https://example.com/a", extractSharedUrl("https://example.com/a"))
    }

    @Test
    fun `extractSharedUrl はURLが無ければnull`() {
        assertNull(extractSharedUrl("URLを含まないテキスト"))
    }

    @Test
    fun `extractSharedUrl はnull安全`() {
        assertNull(extractSharedUrl(null))
    }

    @Test
    fun `extractTitleFromSharedText はURLを除いた残りをタイトルとする`() {
        val url = "https://example.com/article"
        assertEquals("面白い記事", extractTitleFromSharedText("面白い記事 $url", url))
    }

    @Test
    fun `extractTitleFromSharedText はURLのみなら null`() {
        val url = "https://example.com/article"
        assertNull(extractTitleFromSharedText(url, url))
    }

    @Test
    fun `extractTitleTag はtitleタグの中身を返す`() {
        val html = "<html><head><title>テストページ</title></head><body></body></html>"
        assertEquals("テストページ", extractTitleTag(html))
    }

    @Test
    fun `extractTitleTag は属性付きtitleタグにも対応する`() {
        val html = """<title lang="ja">属性付き</title>"""
        assertEquals("属性付き", extractTitleTag(html))
    }

    @Test
    fun `extractTitleTag はHTMLエンティティをデコードする`() {
        val html = "<title>A &amp; B &lt;test&gt; &quot;quoted&quot; &#39;s&#39;</title>"
        assertEquals("A & B <test> \"quoted\" 's'", extractTitleTag(html))
    }

    @Test
    fun `extractTitleTag はtitleタグが無ければnull`() {
        assertNull(extractTitleTag("<html><body>no title</body></html>"))
    }

    @Test
    fun `extractTitleTag は空白のみなら空文字ではなくnullを返す`() {
        assertNull(extractTitleTag("<title>   </title>"))
    }
}
