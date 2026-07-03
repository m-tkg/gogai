import Foundation

struct UpdateCheck: Codable, Sendable {
    let local: String
    let remote: String
    let hasUpdate: Bool
}
