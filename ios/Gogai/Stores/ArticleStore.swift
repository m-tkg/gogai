import Foundation

final class ArticleStore: ObservableObject {
    @Published var articles: [Article] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published private(set) var summarizingIds: Set<Int> = []
    @Published var unreadOnly: Bool {
        didSet { UserDefaults.standard.set(unreadOnly, forKey: "unreadOnly") }
    }
    @Published var summaryOnly: Bool {
        didSet { UserDefaults.standard.set(summaryOnly, forKey: "summaryOnly") }
    }

    private var client: (any APIClientProtocol)?
    private var currentFeedId: Int?
    private var currentGroupId: Int?

    init() {
        self.unreadOnly = UserDefaults.standard.bool(forKey: "unreadOnly")
        self.summaryOnly = UserDefaults.standard.bool(forKey: "summaryOnly")
    }

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchArticles(feedId: Int? = nil, groupId: Int? = nil, unreadOnly: Bool? = nil) async {
        guard let client else { return }
        currentFeedId = feedId
        currentGroupId = groupId
        if let unreadOnly { self.unreadOnly = unreadOnly }
        isLoading = true
        defer { isLoading = false }
        do {
            articles = try await ArticleRepository(client: client).fetchAll(
                feedId: feedId,
                groupId: groupId,
                unreadOnly: self.unreadOnly
            )
        } catch {
            self.error = error
        }
    }

    @MainActor
    func refresh() async {
        // リフレッシュ前のローカル既読状態を保持（markAsRead の API コールが完了前に
        // リフレッシュが走った場合、DB がまだ未読のままでも既読が失われないようにする）
        let localReadIds = Set(articles.filter { $0.isRead }.map { $0.id })
        await fetchArticles(feedId: currentFeedId, groupId: currentGroupId)
        guard !localReadIds.isEmpty else { return }
        articles = articles.map { a in
            guard localReadIds.contains(a.id), !a.isRead else { return a }
            return Article(id: a.id, feed_id: a.feed_id, guid: a.guid,
                           title: a.title, link: a.link, summary: a.summary,
                           content: a.content, published_at: a.published_at,
                           is_read: 1, created_at: a.created_at,
                           ai_summary: a.ai_summary, ai_translation: a.ai_translation)
        }
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
    func markAllAsRead() async {
        let unreadIds = articles.filter { !$0.isRead }.map { $0.id }
        guard !unreadIds.isEmpty, let client else { return }
        // Optimistic update
        articles = articles.map { a in
            guard !a.isRead else { return a }
            return Article(id: a.id, feed_id: a.feed_id, guid: a.guid, title: a.title,
                           link: a.link, summary: a.summary, content: a.content,
                           published_at: a.published_at, is_read: 1, created_at: a.created_at,
                           ai_summary: a.ai_summary, ai_translation: a.ai_translation)
        }
        await withTaskGroup(of: Void.self) { group in
            for id in unreadIds {
                group.addTask {
                    try? await ArticleRepository(client: client).markAsRead(id: id)
                }
            }
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
    func summarize(id: Int) async {
        guard !summarizingIds.contains(id) else { return }
        summarizingIds.insert(id)
        defer { summarizingIds.remove(id) }
        do {
            let result = try await runAI(id: id, action: .summarize)
            if let idx = articles.firstIndex(where: { $0.id == id }) {
                let a = articles[idx]
                articles[idx] = Article(
                    id: a.id, feed_id: a.feed_id, guid: a.guid, title: a.title,
                    link: a.link, summary: a.summary, content: a.content,
                    published_at: a.published_at, is_read: a.is_read, created_at: a.created_at,
                    ai_summary: result.output, ai_translation: a.ai_translation
                )
            }
        } catch {
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
