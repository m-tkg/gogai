import Foundation

struct Article: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let feed_id: Int
    let guid: String
    let title: String?
    let link: String?
    let summary: String?
    let content: String?
    let published_at: String?
    let is_read: Int
    let is_favorite: Int
    let created_at: String
    let ai_summary: String?
    let ai_translation: String?
    let read_at: String?

    var isRead: Bool { is_read == 1 }
    var isFavorite: Bool { is_favorite == 1 }

    /// 既読状態にした新しい Article を返す（フィールドの手動コピーを一箇所に集約）
    func markingAsRead(at dateString: String) -> Article {
        guard !isRead else { return self }
        return Article(id: id, feed_id: feed_id, guid: guid,
                       title: title, link: link, summary: summary,
                       content: content, published_at: published_at,
                       is_read: 1, is_favorite: is_favorite, created_at: created_at,
                       ai_summary: ai_summary, ai_translation: ai_translation,
                       read_at: read_at ?? dateString)
    }
}

enum ArticleSortOrder: String, CaseIterable, Sendable {
    case publishedAt = "published_at"
    case readAt = "read_at"

    var label: String {
        switch self {
        case .publishedAt: return "配信日順"
        case .readAt: return "既読日時順"
        }
    }

    /// ソートアイコンに重ねて表示するバッジ用 SF Symbol 名
    var badgeIconName: String {
        switch self {
        case .publishedAt: return "rss"
        case .readAt: return "envelope.open"
        }
    }
}
