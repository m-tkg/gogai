import XCTest
@testable import Gogai

final class ArticleContentFetcherTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - extractText（HTML → プレーンテキスト）

    func test_extractText_本文のテキストを取り出す() {
        let html = "<html><body><article><h1>見出し</h1><p>本文の段落です。</p></article></body></html>"
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("見出し"))
        XCTAssertTrue(text.contains("本文の段落です。"))
        XCTAssertFalse(text.contains("<"))
    }

    func test_extractText_scriptとstyleは中身ごと除去する() {
        let html = """
        <html><head><title>T</title><style>.a { color: red; }</style></head>
        <body><script>var secret = "code";</script><p>Visible</p>
        <noscript>JS を有効にしてください</noscript></body></html>
        """
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("Visible"))
        XCTAssertFalse(text.contains("secret"), "script の中身が混入してはいけない")
        XCTAssertFalse(text.contains("color: red"), "style の中身が混入してはいけない")
        XCTAssertFalse(text.contains("JS を有効に"), "noscript の中身が混入してはいけない")
    }

    func test_extractText_大文字タグや属性付きタグにも対応する() {
        let html = "<SCRIPT type=\"text/javascript\">bad()</SCRIPT><P CLASS=\"x\">ok</P>"
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertFalse(text.contains("bad()"))
        XCTAssertTrue(text.contains("ok"))
    }

    // MARK: - extractText（<article>/<main> 優先抽出）

    func test_extractText_articleタグがあればナビゲーションやフッターを除外する() {
        // 実テキスト長の下限(minMainContentTextLength = 200)と接しないよう十分長くする
        let articleBody = String(repeating: "これは記事本文です。", count: 40)
        let html = """
        <html><body>
        <nav>Home About Contact Pricing Sign in Sign up Blog</nav>
        <article><p>\(articleBody)</p></article>
        <footer>Copyright 2024 All rights reserved</footer>
        </body></html>
        """
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("これは記事本文です"))
        XCTAssertFalse(text.contains("Sign in"), "article タグ外のナビゲーションは除外される")
        XCTAssertFalse(text.contains("Copyright"), "article タグ外のフッターは除外される")
    }

    func test_extractText_articleタグがなければ従来通りbody全体を使う() {
        let html = "<html><body><nav>Home</nav><p>本文</p></body></html>"
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("Home"))
        XCTAssertTrue(text.contains("本文"))
    }

    func test_extractText_短すぎるarticleタグは無視してbody全体にフォールバックする() {
        let longBody = String(repeating: "テスト", count: 50)
        let html = "<html><body><article>短い</article><p>本当はここに長い本文があります。\(longBody)</p></body></html>"
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("本当はここに長い本文"))
    }

    func test_extractText_複数のarticleタグは最も長いものを採用する() {
        let longBody = String(repeating: "本文です。", count: 60)
        let html = "<html><body><article>短い関連記事</article><article>\(longBody)</article></body></html>"
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("本文です"))
        XCTAssertFalse(text.contains("短い関連記事"))
    }

    /// 9to5mac のようにサイドバーの関連記事カードが <article> で並ぶページの再現。
    /// カードはリンク・div のマークアップが多く HTML バイト長は大きいが、実テキストは短い。
    /// 実テキスト長で判定しないと、本文ではなくカードが選ばれて本体本文が丸ごと消える。
    func test_extractText_テキストが少なくマークアップが多いarticleは無視して本文にフォールバックする() {
        // 実テキストは短い(~12文字)がマークアップで HTML バイト長は肥大したカード
        let card = "<article>" + String(repeating: "<div class=\"card-link-wrapper\"><a href=\"https://example.com/related-post\">", count: 40) + "無関係な関連記事</a></div>" + "</article>"
        // 実テキスト 200 文字超の本体(article/main の外にあり、フォールバックで拾われる)
        let body = "<p>これが本来読みたい記事の本文です。" + String(repeating: "本文が続きます。", count: 30) + "</p>"
        let html = "<html><body>\(card)\(body)</body></html>"
        let text = ArticleContentFetcher.extractText(from: html)
        // 現行実装ではカードが選ばれ本体本文が消える。実テキスト長で判定すれば本体が拾われる。
        XCTAssertTrue(text.contains("これが本来読みたい記事の本文"), "実テキストの薄いカードに本体本文が奪われてはいけない")
    }

    /// 候補選択が HTML バイト長ではなく実テキスト長で行われることを確認する。
    /// マークアップが多く HTML は長いが実テキストが少ない article と、その逆の article を並べる。
    func test_extractText_複数article中は実テキストが最も多いものを採用する() {
        let markupHeavy = "<article>" + String(repeating: "<span class=\"x\"><a href=\"https://example.com/aaaaaaaaaaaaaaaaaaaa\">", count: 30) + "薄いカード</a></span>" + "</article>"
        let textHeavy = "<article><p>厚い本文。" + String(repeating: "厚い本文。", count: 40) + "</p></article>"
        let html = "<html><body>\(markupHeavy)\(textHeavy)</body></html>"
        let text = ArticleContentFetcher.extractText(from: html)
        XCTAssertTrue(text.contains("厚い本文"), "実テキストが最も多い article が採用されるべき")
        XCTAssertFalse(text.contains("薄いカード"))
    }

    // MARK: - fetchPlainText

    func test_fetchPlainText_記事URLからテキストを取得する() async throws {
        MockURLProtocol.requestHandler = { _ in
            (200, Data("<html><body><p>Fetched article body</p><script>x()</script></body></html>".utf8))
        }
        let text = try await ArticleContentFetcher.fetchPlainText(
            from: URL(string: "https://example.com/article")!,
            session: .mock()
        )
        XCTAssertTrue(text.contains("Fetched article body"))
        XCTAssertFalse(text.contains("x()"))
    }

    func test_fetchPlainText_HTTPエラーはthrowする() async {
        MockURLProtocol.requestHandler = { _ in (404, Data()) }
        do {
            _ = try await ArticleContentFetcher.fetchPlainText(
                from: URL(string: "https://example.com/missing")!,
                session: .mock()
            )
            XCTFail("404 はエラーになるべき")
        } catch {
            // expected
        }
    }
}
