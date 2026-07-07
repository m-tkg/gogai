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
        return LocalArticleAI.stripHTML(text)
    }

    /// <article> または <main> で囲われた本文があればその中身を返す。
    /// ナビゲーションバーやフッターがそのまま本文に混入して要約品質が落ちるのを防ぐ。
    /// 該当箇所が複数ある場合は最も長いものを採用し、短すぎる(=関連記事カード等の
    /// 可能性が高い)場合は nil を返して呼び出し元にページ全体へフォールバックさせる。
    private static func extractMainContent(from html: String) -> String? {
        for tag in ["article", "main"] {
            guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>",
                options: .caseInsensitive
            ) else { continue }
            let ns = html as NSString
            let candidates = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
                .compactMap { match -> String? in
                    guard match.numberOfRanges > 1 else { return nil }
                    return ns.substring(with: match.range(at: 1))
                }
            if let longest = candidates.max(by: { $0.count < $1.count }), longest.count > 200 {
                return longest
            }
        }
        return nil
    }
}
