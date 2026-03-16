import Foundation

enum APIError: Error, Sendable {
    case invalidURL
    case networkError(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURL"
        case .networkError(let message):
            return "ネットワークエラー: \(message)"
        case .httpError(let statusCode, _):
            return "HTTPエラー: \(statusCode)"
        case .decodingError(let message):
            return "デコードエラー: \(message)"
        }
    }
}
