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
        let articleBody = String(repeating: "これは記事本文です。", count: 20)
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
