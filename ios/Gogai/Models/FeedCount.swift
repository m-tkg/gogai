import Foundation

/// フィードごとの記事集計（GET /api/articles/counts のレスポンス）。
/// サイドバーのバッジ計算に使用する。記事 0 件のフィードは含まれない。
struct FeedCount: Codable, Equatable, Sendable {
    let feed_id: Int
    let total: Int
    let unread: Int
}
