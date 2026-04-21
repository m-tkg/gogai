import Foundation

protocol APIClientProtocol: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T
    func sendVoid(_ endpoint: Endpoint) async throws
}

struct APIClient: APIClientProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let onNetworkFailure: (@Sendable () -> Void)?

    init(baseURL: URL, session: URLSession = .shared, onNetworkFailure: (@Sendable () -> Void)? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.onNetworkFailure = onNetworkFailure
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let request = try endpoint.urlRequest(baseURL: baseURL)
        let (data, _) = try await fetch(request: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    func sendVoid(_ endpoint: Endpoint) async throws {
        let request = try endpoint.urlRequest(baseURL: baseURL)
        let (_, _) = try await fetch(request: request)
    }

    private func fetch(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            // Why: 接続系エラー（トンネル URL 失効など）は ServerURLManager に
            // キャッシュ破棄 + 再解決を促すためコールバックで通知する。
            // URLError は呼び出し側でリトライ判定するため、そのまま投げ直す。
            onNetworkFailure?()
            throw urlError
        } catch {
            onNetworkFailure?()
            throw APIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            onNetworkFailure?()
            throw APIError.networkError("Invalid response type")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
        return (data, http)
    }
}
