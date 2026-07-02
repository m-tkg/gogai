import XCTest
@testable import Gogai

final class StockSummaryTests: XCTestCase {

    func test_parse_4セクションを分割する() {
        let text = """
        ## 何についての記事か
        AIの進化について

        ## 何の目的で書かれたか
        技術動向を伝えるため

        ## 筆者が一番伝えたいこと
        今後の展望に注目すべき

        ## 要約(20行以内)
        1行目
        2行目
        3行目
        """

        let summary = StockSummary.parse(text)

        XCTAssertEqual(summary?.topic, "AIの進化について")
        XCTAssertEqual(summary?.purpose, "技術動向を伝えるため")
        XCTAssertEqual(summary?.mainMessage, "今後の展望に注目すべき")
        XCTAssertEqual(summary?.summaryLines, ["1行目", "2行目", "3行目"])
    }

    func test_parse_見出しが欠けていればnilを返す() {
        let text = "## 何についての記事か\nA\n## 要約\nB"
        XCTAssertNil(StockSummary.parse(text))
    }

    func test_parse_要約セクションの空行は除去される() {
        let text = """
        ## 何についての記事か
        A
        ## 何の目的で書かれたか
        B
        ## 筆者が一番伝えたいこと
        C
        ## 要約(20行以内)
        1行目

        2行目
        """

        let summary = StockSummary.parse(text)

        XCTAssertEqual(summary?.summaryLines, ["1行目", "2行目"])
    }

    func test_parse_見出し以外のテキストならnilを返す() {
        XCTAssertNil(StockSummary.parse("見出しのないただの文章です。"))
    }
}
