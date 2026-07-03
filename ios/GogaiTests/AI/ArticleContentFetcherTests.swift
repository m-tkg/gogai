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
