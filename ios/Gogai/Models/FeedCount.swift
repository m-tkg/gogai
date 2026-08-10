import Foundation

/// フィードごとの記事集計（GET /api/articles/counts のレスポンス）。
/// サイドバーのバッジ計算に使用する。記事 0 件のフィードは含まれない。
struct FeedCount: Codable, Equatable, Sendable {
    let feed_id: Int
    let total: Int
    let unread: Int
    /// like された記事の件数（like フィルター選択時のバッジに使う）
    let liked: Int
    /// dislike された記事の件数（dislike フィルター選択時のバッジに使う）
    let disliked: Int
}
