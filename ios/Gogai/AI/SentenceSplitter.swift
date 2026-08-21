import Foundation

/// テキストノードの文字列を文単位に分割する(ページ内翻訳の「文単位ミックス」の基礎)。
/// 分割は可逆: 返り値を連結すると必ず元の文字列に一致する(前後の空白は直前の文に付ける)。
/// Android の `SentenceSplitter.kt` と同一アルゴリズム。文ごとの原文ハッシュをサーバーに保存して
/// 両プラットフォームで共有するため、分割結果が一致しなければならない。
enum SentenceSplitter {
    /// 「.」直前の語がこれに含まれる場合は文末とみなさない(省略形)。小文字化して比較する
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "no", "fig",
        "inc", "ltd", "co", "corp", "e.g", "i.e", "cf", "al", "u.s", "u.k", "a.m", "p.m",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]

    /// 文末候補: 和文終端(句点・感嘆・疑問 + 閉じ括弧 + 任意の空白)/ 欧文終端(. ! ? + 閉じ引用 + 必須の空白)
    private static let boundaryPattern =
        "[。！？]+[」』）】〕〉》\"'”’)\\]]*\\s*|[.!?]+[\"'”’)\\]]*\\s+"
    /// 欧文終端の直後が「文の始まり」として妥当な文字か(大文字・数字・開き引用/括弧・非ラテン文字)
    private static let sentenceStartPattern = "^[\\p{Lu}\\p{Lt}\\p{Lo}\\p{N}\"“‘'(\\[「『（【]"
    /// 「.」直前の語(英字とピリオドの連続)
    private static let precedingWordPattern = "[A-Za-z.]+$"

    private static let boundaryRegex = try! NSRegularExpression(pattern: boundaryPattern)
    private static let sentenceStartRegex = try! NSRegularExpression(pattern: sentenceStartPattern)
    private static let precedingWordRegex = try! NSRegularExpression(pattern: precedingWordPattern)

    static func split(_ text: String) -> [String] {
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return [] }

        var pieces: [String] = []
        var pieceStart = 0
        for match in boundaryRegex.matches(in: text, range: NSRange(location: 0, length: length)) {
            let end = match.range.location + match.range.length
            // 末尾に達した境界は切る必要がない(残りが空になる)
            guard end < length else { break }
            let punct = ns.character(at: match.range.location)
            if isLatinTerminal(punct) {
                let rest = ns.substring(from: end)
                guard sentenceStartRegex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) != nil else { continue }
                if punct == 0x2E /* . */, isAbbreviation(before: match.range.location, in: ns) { continue }
            }
            pieces.append(ns.substring(with: NSRange(location: pieceStart, length: end - pieceStart)))
            pieceStart = end
        }
        pieces.append(ns.substring(from: pieceStart))
        return pieces
    }

    private static func isLatinTerminal(_ c: unichar) -> Bool {
        c == 0x2E || c == 0x21 || c == 0x3F // . ! ?
    }

    /// 「.」の直前の語が省略形、または 1 文字の大文字(イニシャル)なら文末とみなさない
    private static func isAbbreviation(before location: Int, in ns: NSString) -> Bool {
        let head = ns.substring(to: location)
        guard let match = precedingWordRegex.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) else {
            return false
        }
        let word = (head as NSString).substring(with: match.range)
        if word.count == 1, word.uppercased() == word, word.lowercased() != word { return true }
        return abbreviations.contains(word.lowercased())
    }
}
