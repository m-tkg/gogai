import Foundation

struct Group: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let created_at: String
}
