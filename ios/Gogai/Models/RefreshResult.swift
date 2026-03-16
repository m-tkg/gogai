import Foundation

struct RefreshResult: Codable, Sendable {
    let refreshed: Int
    let failed: Int
}
