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
    let created_at: String
    let read_at: String?

    var isRead: Bool { is_read == 1 }

    /// 指定フィールドだけ差し替えた新しい Article を返す（全フィールド手動コピーの集約先）
    func updating(isRead: Int? = nil, readAt: FieldUpdate<String> = .keep) -> Article {
        Article(id: id, feed_id: feed_id, guid: guid,
                title: title, link: link, summary: summary,
                content: content, published_at: published_at,
                is_read: isRead ?? is_read,
                created_at: created_at,
                read_at: readAt.apply(to: read_at))
    }

    /// 既読状態にした新しい Article を返す
    func markingAsRead(at dateString: String) -> Article {
        guard !isRead else { return self }
        return updating(isRead: 1, readAt: .set(read_at ?? dateString))
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
