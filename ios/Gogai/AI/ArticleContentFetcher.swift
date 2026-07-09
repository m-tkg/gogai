import Foundation

/// 記事 URL から本文テキストを取得する。
/// SFSafariViewController は表示中ページのテキストを取得できないため、
/// AI に渡す本文はアプリが記事 URL を直接フェッチして抽出する。
enum ArticleContentFetcher {
    /// 記事 URL の HTML を取得し、プレーンテキストを返す
    static func fetchPlainText(from url: URL, session: URLSession = .shared) async throws -> String {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return extractText(from: html)
    }

    /// HTML からプレーンテキストを抽出する。
    /// script / style / noscript / head は中身ごと除去してからタグを剥がす。
    /// <article>/<main> があればナビゲーション・フッター等を除いた本文だけを使う。
    static func extractText(from html: String) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "head"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        if let mainContent = extractMainContent(from: text) {
            text = mainContent
        }
        return stripHTML(text)
    }

    /// HTML タグ・主要エンティティ・数値文字参照を除去してプレーンテキスト化する。
    /// LocalArticleAI（要約/翻訳のプロンプト整形）と StockSummarizer（ストック要約)の
    /// 両方が呼ぶ、本来 HTML 抽出の責務を持つこちら側で所有する。
    static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“",
            "&hellip;": "…", "&mldr;": "…", "&mdash;": "—", "&ndash;": "–",
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = decodeNumericEntities(text)
        return text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 数値文字参照(&#NNN; / &#xHHHH;)をデコードする。アイコンフォント用の私用領域
    /// (Private Use Area)コードポイントはテキストとして意味を持たないため空文字にする。
    private static func decodeNumericEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#x?[0-9a-fA-F]+;", options: .caseInsensitive) else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let token = ns.substring(with: match.range)
            if let scalar = decodeEntityScalar(token), !isPrivateUse(scalar) {
                result += String(Character(scalar))
            }
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    private static func decodeEntityScalar(_ token: String) -> Unicode.Scalar? {
        let inner = token.dropFirst(2).dropLast() // "&#" 接頭辞と ";" 接尾辞を除去
        let isHex = inner.hasPrefix("x") || inner.hasPrefix("X")
        let digits = isHex ? inner.dropFirst() : inner[...]
        guard let value = UInt32(digits, radix: isHex ? 16 : 10) else { return nil }
        return Unicode.Scalar(value)
    }

    private static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool {
        (0xE000...0xF8FF).contains(scalar.value)
            || (0xF0000...0xFFFFD).contains(scalar.value)
            || (0x100000...0x10FFFD).contains(scalar.value)
    }

    /// これ未満の実テキストしか持たない <article>/<main> は本文とみなさない下限文字数。
    private static let minMainContentTextLength = 200

    /// <article> または <main> で囲われた本文があればその中身を返す。
    /// ナビゲーションバーやフッターがそのまま本文に混入して要約品質が落ちるのを防ぐ。
    /// 該当箇所が複数ある場合は実テキストが最も多いものを採用し、実テキストが少ない
    /// (=関連記事カード等の可能性が高い)場合は nil を返して呼び出し元にページ全体へ
    /// フォールバックさせる。
    ///
    /// 判定は HTML バイト長ではなく stripHTML 後の実テキスト長で行う。9to5mac 等では
    /// サイドバーの関連記事カードが <article> で並び、リンク・div のマークアップで HTML は
    /// 肥大するが実テキストは数十文字しかない。HTML 長で選ぶとこのカードが本文を奪い、
    /// 無関係な内容の要約になる。
    private static func extractMainContent(from html: String) -> String? {
        for tag in ["article", "main"] {
            guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>",
                options: .caseInsensitive
            ) else { continue }
            let ns = html as NSString
            let candidates = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
                .compactMap { match -> (html: String, textLength: Int)? in
                    guard match.numberOfRanges > 1 else { return nil }
                    let inner = ns.substring(with: match.range(at: 1))
                    return (inner, stripHTML(inner).count)
                }
            if let best = candidates.max(by: { $0.textLength < $1.textLength }),
               best.textLength >= minMainContentTextLength {
                return best.html
            }
        }
        return nil
    }
}
