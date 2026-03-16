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

    func update(id: Int, name: String) async throws -> Group {
        try await client.send(try .put("/api/groups/\(id)", body: ["name": name]))
    }

    func delete(id: Int) async throws {
        try await client.sendVoid(.delete("/api/groups/\(id)"))
    }

    func refresh(id: Int) async throws -> RefreshResult {
        try await client.send(.post("/api/groups/\(id)/refresh"))
    }
}
