import Foundation

struct Endpoint: Sendable {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    let body: Data?

    enum HTTPMethod: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
    }

    static func get(_ path: String, queryItems: [URLQueryItem]? = nil) -> Endpoint {
        Endpoint(path: path, method: .get, queryItems: queryItems)
    }

    static func post(_ path: String) -> Endpoint {
        Endpoint(path: path, method: .post)
    }

    static func post<B: Encodable & Sendable>(_ path: String, body: B) throws -> Endpoint {
        let data = try JSONEncoder().encode(body)
        return Endpoint(path: path, method: .post, body: data)
    }

    static func put<B: Encodable & Sendable>(_ path: String, body: B) throws -> Endpoint {
        let data = try JSONEncoder().encode(body)
        return Endpoint(path: path, method: .put, body: data)
    }

    static func delete(_ path: String) -> Endpoint {
        Endpoint(path: path, method: .delete)
    }

    func urlRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems?.isEmpty == false ? queryItems : nil
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }
}
