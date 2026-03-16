import Foundation

final class ArticleStore: ObservableObject {
    @Published var articles: [Article] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?

    private var client: (any APIClientProtocol)?
    private var currentFeedId: Int?
    private var currentGroupId: Int?
    private var currentUnreadOnly: Bool = false

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchArticles(feedId: Int? = nil, groupId: Int? = nil, unreadOnly: Bool = false) async {
        guard let client else { return }
        currentFeedId = feedId
        currentGroupId = groupId
        currentUnreadOnly = unreadOnly
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await ArticleRepository(client: client).fetchAll(
                feedId: feedId,
                groupId: groupId,
                unreadOnly: unreadOnly
            )
        } catch {
            self.error = error
        }
    }

    @MainActor
    func refresh() async {
        await fetchArticles(feedId: currentFeedId, groupId: currentGroupId, unreadOnly: currentUnreadOnly)
    }

    // Optimistic update: immediately update local state, rollback on failure
    @MainActor
    func markAsRead(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]

        articles[idx] = Article(
            id: original.id, feed_id: original.feed_id, guid: original.guid,
            title: original.title, link: original.link, summary: original.summary,
            content: original.content, published_at: original.published_at,
            is_read: 1, created_at: original.created_at,
            ai_summary: original.ai_summary, ai_translation: original.ai_translation
        )

        do {
            try await ArticleRepository(client: client).markAsRead(id: id)
        } catch {
            if let rollbackIdx = articles.firstIndex(where: { $0.id == id }) {
                articles[rollbackIdx] = original
            }
            self.error = error
        }
    }

    @MainActor
    func markAsUnread(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]

        articles[idx] = Article(
            id: original.id, feed_id: original.feed_id, guid: original.guid,
            title: original.title, link: original.link, summary: original.summary,
            content: original.content, published_at: original.published_at,
            is_read: 0, created_at: original.created_at,
            ai_summary: original.ai_summary, ai_translation: original.ai_translation
        )

        do {
            try await ArticleRepository(client: client).markAsUnread(id: id)
        } catch {
            if let rollbackIdx = articles.firstIndex(where: { $0.id == id }) {
                articles[rollbackIdx] = original
            }
            self.error = error
        }
    }

    @MainActor
    func runAI(id: Int, action: ArticleRepository.AIAction, force: Bool = false) async throws -> ArticleRepository.AIResult {
        guard let client else { throw APIError.invalidURL }
        return try await ArticleRepository(client: client).runAI(id: id, action: action, force: force)
    }

    func unreadCount(for feedId: Int?) -> Int {
        let filtered = feedId.map { fid in articles.filter { $0.feed_id == fid } } ?? articles
        return filtered.filter { !$0.isRead }.count
    }
}
