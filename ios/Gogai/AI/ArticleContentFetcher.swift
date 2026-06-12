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
    static func extractText(from html: String) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "head"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return LocalArticleAI.stripHTML(text)
    }
}
