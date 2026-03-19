import Foundation

struct Group: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let is_secret: Int
    let created_at: String

    var isSecret: Bool { is_secret == 1 }
}
