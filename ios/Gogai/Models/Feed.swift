import Foundation

struct Feed: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let url: String
    let title: String?
    let favicon_url: String?
    let group_id: Int?
    let last_fetched_at: String?
    let created_at: String
    let display_order: Int
}
