import Foundation

final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings?
    @Published private(set) var updateCheck: UpdateCheck?
    @Published private(set) var isLoading = false
    @Published var error: Error?

    private var client: (any APIClientProtocol)?

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchSettings() async {
        guard let client else { return }
        do {
            settings = try await SettingsRepository(client: client).fetch()
        } catch {
            self.error = error
        }
    }

    @MainActor
    func updateRetentionDays(_ days: Int) async throws {
        guard let client else { return }
        settings = try await SettingsRepository(client: client).update(retentionDays: days)
    }

    @MainActor
    func checkUpdate() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            updateCheck = try await SettingsRepository(client: client).checkUpdate()
        } catch {
            self.error = error
        }
    }

    @MainActor
    func restart() async throws -> String {
        guard let client else { throw APIError.invalidURL }
        return try await SettingsRepository(client: client).restart()
    }
}
