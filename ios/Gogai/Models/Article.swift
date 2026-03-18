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
    let ai_summary: String?
    let ai_translation: String?
    let read_at: String?

    var isRead: Bool { is_read == 1 }
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
}
