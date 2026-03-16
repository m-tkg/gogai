import Foundation

struct SettingsRepository: Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func fetch() async throws -> Settings {
        try await client.send(.get("/api/settings"))
    }

    func update(retentionDays: Int) async throws -> Settings {
        try await client.send(try .put("/api/settings", body: ["retention_days": retentionDays]))
    }

    func checkUpdate() async throws -> UpdateCheck {
        try await client.send(.get("/api/admin/update-check"))
    }

    func restart() async throws -> String {
        struct RestartResult: Codable, Sendable { let output: String }
        let result: RestartResult = try await client.send(.post("/api/admin/restart"))
        return result.output
    }
}
