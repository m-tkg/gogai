import Foundation

final class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var error: Error?

    private var client: (any APIClientProtocol)?
    private var onRefreshComplete: (() -> Void)?

    func configure(with client: any APIClientProtocol, onRefreshComplete: (() -> Void)? = nil) {
        self.client = client
        self.onRefreshComplete = onRefreshComplete
    }

    @MainActor
    func fetchFeeds() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            feeds = try await FeedRepository(client: client).fetchAll()
        } catch {
            self.error = error
        }
    }

    @MainActor
    func createFeed(url: String, groupId: Int? = nil) async throws {
        guard let client else { return }
        let newFeed = try await FeedRepository(client: client).create(url: url, groupId: groupId)
        feeds.append(newFeed)
    }

    @MainActor
    func updateFeed(id: Int, title: String? = nil, groupId: Int?? = nil) async throws {
        guard let client else { return }
        let updated = try await FeedRepository(client: client).update(id: id, title: title, groupId: groupId)
        if let idx = feeds.firstIndex(where: { $0.id == id }) {
            feeds[idx] = updated
        }
    }

    @MainActor
    func deleteFeed(id: Int) async throws {
        guard let client else { return }
        try await FeedRepository(client: client).delete(id: id)
        feeds.removeAll { $0.id == id }
    }

    @MainActor
    func refreshFeed(id: Int) async throws -> RefreshResult {
        guard let client else { throw APIError.invalidURL }
        let result = try await FeedRepository(client: client).refresh(id: id)
        onRefreshComplete?()
        return result
    }

    @MainActor
    func refreshAll() async throws -> RefreshResult {
        guard let client else { throw APIError.invalidURL }
        isRefreshing = true
        defer { isRefreshing = false }
        let result = try await FeedRepository(client: client).refreshAll()
        onRefreshComplete?()
        return result
    }

    func feeds(for groupId: Int?) -> [Feed] {
        if let groupId {
            return feeds.filter { $0.group_id == groupId }
        }
        return feeds
    }
}
