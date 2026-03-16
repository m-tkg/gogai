import Foundation

struct FeedRepository: Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetchAll() async throws -> [Feed] {
        try await client.send(.get("/api/feeds"))
    }

    func create(url: String, groupId: Int? = nil) async throws -> Feed {
        struct Body: Encodable, Sendable {
            let url: String
            let groupId: Int?
        }
        return try await client.send(try .post("/api/feeds", body: Body(url: url, groupId: groupId)))
    }

    func update(id: Int, title: String? = nil, groupId: Int?? = nil) async throws -> Feed {
        struct Body: Encodable, Sendable {
            let title: String?
            let groupId: Int??
            enum CodingKeys: String, CodingKey { case title, groupId }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(title, forKey: .title)
                if let groupId {
                    try container.encode(groupId, forKey: .groupId)
                }
            }
        }
        return try await client.send(try .put("/api/feeds/\(id)", body: Body(title: title, groupId: groupId)))
    }

    func delete(id: Int) async throws {
        try await client.sendVoid(.delete("/api/feeds/\(id)"))
    }

    func refresh(id: Int) async throws -> RefreshResult {
        try await client.send(.post("/api/feeds/\(id)/refresh"))
    }

    func refreshAll() async throws -> RefreshResult {
        try await client.send(.post("/api/feeds/refresh-all"))
    }
}
