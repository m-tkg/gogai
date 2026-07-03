import Foundation

struct Group: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let is_secret: Int
    let created_at: String
    let display_order: Int

    var isSecret: Bool { is_secret == 1 }
}
