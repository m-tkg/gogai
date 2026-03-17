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
        case .httpError(let statusCode, let body):
            // body から {"error":"..."} を取り出して表示
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let msg = json["error"] {
                return "HTTPエラー \(statusCode): \(msg)"
            }
            return body.isEmpty ? "HTTPエラー: \(statusCode)" : "HTTPエラー \(statusCode): \(body)"
        case .decodingError(let message):
            return "デコードエラー: \(message)"
        }
    }
}
