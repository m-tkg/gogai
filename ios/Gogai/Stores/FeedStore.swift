import Foundation

final class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var error: Error?

    private let cache: AppCache
    private var client: (any APIClientProtocol)?
    private var onRefreshComplete: (() -> Void)?

    init(cache: AppCache = .shared) {
        self.cache = cache
        // 起動時にキャッシュからフィード一覧を読み込む
        self.feeds = cache.loadFeeds()
    }

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
            cache.saveFeeds(feeds)
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

    @MainActor
    func reorderFeeds(from source: IndexSet, to destination: Int, groupId: Int?) async throws {
        guard let client else { return }
        // feeds(for: nil) は全フィードを返すため、group_id で直接フィルタする
        var groupFeeds = feeds.filter { $0.group_id == groupId }
        let otherFeeds = feeds.filter { $0.group_id != groupId }
        groupFeeds.move(fromOffsets: source, toOffset: destination)
        let ids = groupFeeds.map { $0.id }
        try await FeedRepository(client: client).reorder(ids: ids)
        feeds = otherFeeds + groupFeeds
    }
}
