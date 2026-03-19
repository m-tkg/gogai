import Foundation

struct GroupRepository: Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetchAll() async throws -> [Group] {
        try await client.send(.get("/api/groups"))
    }

    func create(name: String) async throws -> Group {
        try await client.send(try .post("/api/groups", body: ["name": name]))
    }

    func update(id: Int, name: String, isSecret: Int? = nil) async throws -> Group {
        if let isSecret {
            struct BodyWithSecret: Encodable, Sendable {
                let name: String
                let is_secret: Int
            }
            return try await client.send(try .put("/api/groups/\(id)", body: BodyWithSecret(name: name, is_secret: isSecret)))
        } else {
            struct Body: Encodable, Sendable {
                let name: String
            }
            return try await client.send(try .put("/api/groups/\(id)", body: Body(name: name)))
        }
    }

    func delete(id: Int) async throws {
        try await client.sendVoid(.delete("/api/groups/\(id)"))
    }

    func refresh(id: Int) async throws -> RefreshResult {
        try await client.send(.post("/api/groups/\(id)/refresh"))
    }

    func reorder(ids: [Int]) async throws {
        struct Body: Encodable, Sendable { let ids: [Int] }
        try await client.sendVoid(try .patch("/api/groups/reorder", body: Body(ids: ids)))
    }
}
