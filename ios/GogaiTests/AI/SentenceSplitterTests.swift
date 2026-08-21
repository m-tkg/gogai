import XCTest
@testable import Gogai

final class SentenceSplitterTests: XCTestCase {

    func test_和文は句点で分割し句点と後続の空白は前の文に付く() {
        let pieces = SentenceSplitter.split("朝7時に起きました。朝ご飯を食べた。 調子が悪かった。")
        XCTAssertEqual(pieces, ["朝7時に起きました。", "朝ご飯を食べた。 ", "調子が悪かった。"])
    }

    func test_和文の閉じ括弧は前の文に含める() {
        let pieces = SentenceSplitter.split("彼は「行く。」と言った。本当か？」と返した。")
        XCTAssertEqual(pieces, ["彼は「行く。」", "と言った。", "本当か？」", "と返した。"])
    }

    func test_欧文はピリオドと空白の後に大文字が続く位置で分割する() {
        let pieces = SentenceSplitter.split("I had breakfast. It was good! Really? Yes.")
        XCTAssertEqual(pieces, ["I had breakfast. ", "It was good! ", "Really? ", "Yes."])
    }

    func test_欧文のピリオドの後が小文字なら分割しない() {
        let pieces = SentenceSplitter.split("See the docs e.g. the guide. Then go.")
        XCTAssertEqual(pieces, ["See the docs e.g. the guide. ", "Then go."])
    }

    func test_省略形やイニシャルの後では分割しない() {
        XCTAssertEqual(SentenceSplitter.split("Dr. Smith arrived. He sat."), ["Dr. Smith arrived. ", "He sat."])
        XCTAssertEqual(SentenceSplitter.split("J. K. Rowling wrote it. Read it."), ["J. K. Rowling wrote it. ", "Read it."])
        XCTAssertEqual(SentenceSplitter.split("The U.S. government acted. It worked."), ["The U.S. government acted. ", "It worked."])
    }

    func test_閉じ引用符の後で分割する() {
        let pieces = SentenceSplitter.split("He said \"Go.\" She left. “Why?” Nobody knew.")
        XCTAssertEqual(pieces, ["He said \"Go.\" ", "She left. ", "“Why?” ", "Nobody knew."])
    }

    func test_小数点や数字の途中では分割しない() {
        XCTAssertEqual(SentenceSplitter.split("Version 3.5 is out. Get it."), ["Version 3.5 is out. ", "Get it."])
    }

    func test_文末記号がなければ全体を1文にする() {
        XCTAssertEqual(SentenceSplitter.split("Home"), ["Home"])
        XCTAssertEqual(SentenceSplitter.split("  見出し  "), ["  見出し  "])
    }

    func test_末尾の句点では分割しない() {
        XCTAssertEqual(SentenceSplitter.split("終わり。"), ["終わり。"])
        XCTAssertEqual(SentenceSplitter.split("Done. "), ["Done. "])
    }

    func test_空文字は空配列() {
        XCTAssertEqual(SentenceSplitter.split(""), [])
    }

    func test_分割結果を連結すると元の文字列に一致する() {
        let samples = [
            "  Leading space. Then 改行\n続く。最後 ",
            "Mixed 日本語 and English. 日本語の文。Next one!  Yes?\tTab.",
            "No terminal punctuation at all",
            "...ellipsis... then more... And More.",
        ]
        for sample in samples {
            XCTAssertEqual(SentenceSplitter.split(sample).joined(), sample, "可逆でなければならない: \(sample)")
        }
    }

    func test_1文だけの入力は再分割しても同じ1文になる() {
        // 再翻訳時は span ごとに分かれたテキストノードを再走査するため、各文単体の分割が冪等である必要がある
        for piece in SentenceSplitter.split("I had breakfast. It was good! 朝ご飯。おいしかった。") {
            XCTAssertEqual(SentenceSplitter.split(piece), [piece])
        }
    }
}
