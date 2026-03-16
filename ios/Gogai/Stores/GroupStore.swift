import Foundation

final class GroupStore: ObservableObject {
    @Published var groups: [Group] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?

    private var client: (any APIClientProtocol)?

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchGroups() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await GroupRepository(client: client).fetchAll()
        } catch {
            self.error = error
        }
    }

    @MainActor
    func createGroup(name: String) async throws {
        guard let client else { return }
        let newGroup = try await GroupRepository(client: client).create(name: name)
        groups.append(newGroup)
    }

    @MainActor
    func updateGroup(id: Int, name: String) async throws {
        guard let client else { return }
        let updated = try await GroupRepository(client: client).update(id: id, name: name)
        if let idx = groups.firstIndex(where: { $0.id == id }) {
            groups[idx] = updated
        }
    }

    @MainActor
    func deleteGroup(id: Int) async throws {
        guard let client else { return }
        try await GroupRepository(client: client).delete(id: id)
        groups.removeAll { $0.id == id }
    }

    @MainActor
    func refreshGroup(id: Int) async throws -> RefreshResult {
        guard let client else { throw APIError.invalidURL }
        return try await GroupRepository(client: client).refresh(id: id)
    }
}
