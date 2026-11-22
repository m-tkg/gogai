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
        try await client.send(.get("/api/admin/update-check", headers: adminHeaders))
    }

    func restart() async throws -> String {
        struct RestartResult: Codable, Sendable { let output: String }
        let result: RestartResult = try await client.send(.post("/api/admin/restart", headers: adminHeaders))
        return result.output
    }

    /// サーバーの管理 API が要求する認証ヘッダー(サーバー側は ADMIN_SECRET 未設定なら全拒否)。
    /// 未設定(Keychain に何も保存していない)の場合はヘッダーを送らない(サーバーに拒否される)。
    private var adminHeaders: [String: String] {
        guard let secret = KeychainStore.get(forKey: KeychainStore.adminSecretKey), !secret.isEmpty else {
            return [:]
        }
        return ["X-Admin-Secret": secret]
    }
}
