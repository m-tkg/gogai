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
    /// ユーザーが「好み」と表明した日時。nil = 未 like。
    /// 外部のキュレーション AI へ渡すシグナルで、既読とは独立した軸。
    /// 既存の Article(...) 呼び出しを壊さないようデフォルト値を持たせている。
    var liked_at: String? = nil
    /// liked_at の対になる負のシグナル。nil = 未 dislike。liked_at とは排他。
    var disliked_at: String? = nil

    var isRead: Bool { is_read == 1 }
    var isLiked: Bool { liked_at != nil }
    var isDisliked: Bool { disliked_at != nil }

    /// 指定フィールドだけ差し替えた新しい Article を返す（全フィールド手動コピーの集約先）
    func updating(
        isRead: Int? = nil,
        readAt: FieldUpdate<String> = .keep,
        likedAt: FieldUpdate<String> = .keep,
        dislikedAt: FieldUpdate<String> = .keep
    ) -> Article {
        Article(id: id, feed_id: feed_id, guid: guid,
                title: title, link: link, summary: summary,
                content: content, published_at: published_at,
                is_read: isRead ?? is_read,
                created_at: created_at,
                read_at: readAt.apply(to: read_at),
                liked_at: likedAt.apply(to: liked_at),
                disliked_at: dislikedAt.apply(to: disliked_at))
    }

    /// 既読状態にした新しい Article を返す
    func markingAsRead(at dateString: String) -> Article {
        guard !isRead else { return self }
        return updating(isRead: 1, readAt: .set(read_at ?? dateString))
    }
}

/// 記事一覧のフィルター（フィードページ・記事一覧ページのフッターで排他選択する）
enum ArticleFilter: String, CaseIterable, Sendable {
    case all
    case unread
    case liked
    case disliked

    var label: String {
        switch self {
        case .all: return "全て"
        case .unread: return "未読のみ"
        case .liked: return "like"
        case .disliked: return "dislike"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "list.bullet"
        case .unread: return "envelope.badge"
        case .liked: return "hand.thumbsup"
        case .disliked: return "hand.thumbsdown"
        }
    }

    /// サーバーから全件を取得するフィルターかどうか。
    /// false のフィルターは部分フェッチなので、全記事キャッシュ（ArticleCollection）を上書きしない。
    var isFullFetch: Bool { self == .all }
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
