import Foundation

final class ArticleStore: ObservableObject {
    @Published var articles: [Article] = []
    /// 全フィードの記事キャッシュ（未読バッジの計算に使用）
    /// articles はフィルタ表示用なので特定フィードのみになることがあるが、
    /// allArticles は常に全体を保持して sidebar の未読カウントを正確にする
    @Published private(set) var allArticles: [Article] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published private(set) var summarizingIds: Set<Int> = []
    @Published var unreadOnly: Bool {
        didSet { UserDefaults.standard.set(unreadOnly, forKey: "unreadOnly") }
    }
    @Published var summaryOnly: Bool {
        didSet { UserDefaults.standard.set(summaryOnly, forKey: "summaryOnly") }
    }
    @Published var sortOrder: ArticleSortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }

    private var client: (any APIClientProtocol)?
    private var currentFeedId: Int?
    private var currentGroupId: Int?
    private var currentIncludeSecret: Bool = false
    /// 最後の fetchArticles が unreadOnly=true で実行されたかどうか
    /// refresh() での既読記事保持の判定に使用する
    /// unreadOnly=false で読み込まれた記事は「既読になった記事」と区別できないため保持しない
    private var loadedWithUnreadOnly: Bool = false
    /// 並行する fetchArticles 呼び出しで古い結果が上書きしないよう管理する世代カウンター
    private var fetchGeneration = 0
    /// isLoading を正確に管理するための実行中タスク数
    private var loadingTaskCount = 0

    init() {
        self.unreadOnly = UserDefaults.standard.bool(forKey: "unreadOnly")
        self.summaryOnly = UserDefaults.standard.bool(forKey: "summaryOnly")
        let savedSort = UserDefaults.standard.string(forKey: "sortOrder") ?? ""
        self.sortOrder = ArticleSortOrder(rawValue: savedSort) ?? .publishedAt
    }

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchArticles(feedId: Int? = nil, groupId: Int? = nil, unreadOnly: Bool? = nil, includeSecret: Bool = false) async {
        guard let client else { return }
        currentFeedId = feedId
        currentGroupId = groupId
        currentIncludeSecret = includeSecret
        if let unreadOnly { self.unreadOnly = unreadOnly }
        fetchGeneration += 1
        let myGeneration = fetchGeneration
        loadingTaskCount += 1
        isLoading = true
        defer {
            loadingTaskCount -= 1
            if loadingTaskCount == 0 { isLoading = false }
        }
        do {
            let fetched = try await ArticleRepository(client: client).fetchAll(
                feedId: feedId,
                groupId: groupId,
                unreadOnly: self.unreadOnly,
                sortOrder: self.sortOrder,
                includeSecret: includeSecret
            )
            // 新しいフェッチが始まっていれば古い結果は破棄する
            guard myGeneration == fetchGeneration else { return }
            articles = fetched
            loadedWithUnreadOnly = self.unreadOnly
            mergeIntoAllArticles(fetched, feedId: feedId, groupId: groupId)
        } catch {
            if myGeneration == fetchGeneration { self.error = error }
        }
    }

    @MainActor
    func refresh() async {
        // refresh 前に既読になっていた記事を保存する
        // unreadOnly=true かつ前回フェッチも unreadOnly=true だった場合のみ保存する
        // （unreadOnly=false で読み込まれた記事は既読・未読が混在しており、
        //   「このセッションで読んだ記事」と区別できないため保持しない）
        let previouslyReadArticles = loadedWithUnreadOnly ? articles.filter { $0.isRead } : []

        await fetchArticles(feedId: currentFeedId, groupId: currentGroupId, includeSecret: currentIncludeSecret)

        guard !previouslyReadArticles.isEmpty else { return }

        // API レスポンス遅延による未読状態の不一致を修正（fetch 結果に含まれている場合）
        let localReadIds = Set(previouslyReadArticles.map { $0.id })
        articles = articles.map { a in
            guard localReadIds.contains(a.id), !a.isRead else { return a }
            return Article(id: a.id, feed_id: a.feed_id, guid: a.guid,
                           title: a.title, link: a.link, summary: a.summary,
                           content: a.content, published_at: a.published_at,
                           is_read: 1, created_at: a.created_at,
                           ai_summary: a.ai_summary, ai_translation: a.ai_translation,
                           read_at: a.read_at)
        }
        allArticles = allArticles.map { a in
            guard localReadIds.contains(a.id), !a.isRead else { return a }
            return Article(id: a.id, feed_id: a.feed_id, guid: a.guid,
                           title: a.title, link: a.link, summary: a.summary,
                           content: a.content, published_at: a.published_at,
                           is_read: 1, created_at: a.created_at,
                           ai_summary: a.ai_summary, ai_translation: a.ai_translation,
                           read_at: a.read_at)
        }

        // unreadOnly: true の場合、fetch 結果に含まれなかった既読記事をリストに保持する
        // （このセッションで読んだ記事が自動 refresh で消えないようにするため）
        // allArticles は未読バッジ計算用のため、既読になった記事は追加不要
        if unreadOnly {
            let newIds = Set(articles.map { $0.id })
            let toPreserve = previouslyReadArticles.filter { !newIds.contains($0.id) }
            if !toPreserve.isEmpty {
                articles = (articles + toPreserve).sorted { a, b in
                    switch sortOrder {
                    case .publishedAt:
                        let aDate = a.published_at ?? a.created_at
                        let bDate = b.published_at ?? b.created_at
                        return aDate > bDate
                    case .readAt:
                        let aDate = a.read_at ?? a.published_at ?? a.created_at
                        let bDate = b.read_at ?? b.published_at ?? b.created_at
                        return aDate > bDate
                    }
                }
            }
        }
    }

    // Optimistic update: immediately update local state, rollback on failure
    @MainActor
    func markAsRead(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let updated = Article(
            id: original.id, feed_id: original.feed_id, guid: original.guid,
            title: original.title, link: original.link, summary: original.summary,
            content: original.content, published_at: original.published_at,
            is_read: 1, created_at: original.created_at,
            ai_summary: original.ai_summary, ai_translation: original.ai_translation,
            read_at: nowISO
        )
        articles[idx] = updated
        updateAllArticles(updated)

        do {
            try await ArticleRepository(client: client).markAsRead(id: id)
        } catch {
            articles[idx] = original
            updateAllArticles(original)
            self.error = error
        }
    }

    @MainActor
    func markAllAsRead() async {
        let unread = articles.filter { !$0.isRead }
        guard !unread.isEmpty, let client else { return }

        // Optimistic update
        let nowISO = ISO8601DateFormatter().string(from: Date())
        articles = articles.map { a in
            guard !a.isRead else { return a }
            return Article(id: a.id, feed_id: a.feed_id, guid: a.guid, title: a.title,
                           link: a.link, summary: a.summary, content: a.content,
                           published_at: a.published_at, is_read: 1, created_at: a.created_at,
                           ai_summary: a.ai_summary, ai_translation: a.ai_translation,
                           read_at: nowISO)
        }
        for a in articles { updateAllArticles(a) }

        // API calls with rollback on failure
        for original in unread {
            do {
                try await ArticleRepository(client: client).markAsRead(id: original.id)
            } catch {
                if let idx = articles.firstIndex(where: { $0.id == original.id }) {
                    articles[idx] = original
                }
                updateAllArticles(original)
                self.error = error
            }
        }
    }

    @MainActor
    func markAsUnread(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]
        let updated = Article(
            id: original.id, feed_id: original.feed_id, guid: original.guid,
            title: original.title, link: original.link, summary: original.summary,
            content: original.content, published_at: original.published_at,
            is_read: 0, created_at: original.created_at,
            ai_summary: original.ai_summary, ai_translation: original.ai_translation,
            read_at: nil
        )
        articles[idx] = updated
        updateAllArticles(updated)

        do {
            try await ArticleRepository(client: client).markAsUnread(id: id)
        } catch {
            articles[idx] = original
            updateAllArticles(original)
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
                let updated = Article(
                    id: a.id, feed_id: a.feed_id, guid: a.guid, title: a.title,
                    link: a.link, summary: a.summary, content: a.content,
                    published_at: a.published_at, is_read: a.is_read, created_at: a.created_at,
                    ai_summary: result.output, ai_translation: a.ai_translation,
                    read_at: a.read_at
                )
                articles[idx] = updated
                updateAllArticles(updated)
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
        // allArticles（全フィードキャッシュ）を優先して使用する
        let source = allArticles.isEmpty ? articles : allArticles
        let filtered = feedId.map { fid in source.filter { $0.feed_id == fid } } ?? source
        return filtered.filter { !$0.isRead }.count
    }

    func unreadCount(forGroupFeedIds feedIds: [Int]) -> Int {
        let source = allArticles.isEmpty ? articles : allArticles
        let feedIdSet = Set(feedIds)
        return source.filter { feedIdSet.contains($0.feed_id) && !$0.isRead }.count
    }

    // MARK: - Private

    /// フェッチ結果を allArticles にマージする
    /// 全記事フェッチ時は全置換、特定フィード/グループのフェッチ時は該当フィードの記事を差し替える
    private func mergeIntoAllArticles(_ fetched: [Article], feedId: Int?, groupId: Int?) {
        if feedId == nil && groupId == nil {
            allArticles = fetched
        } else {
            let fetchedFeedIds = Set(fetched.map { $0.feed_id })
            allArticles = allArticles.filter { !fetchedFeedIds.contains($0.feed_id) } + fetched
        }
    }

    /// allArticles 内の該当記事を更新する
    private func updateAllArticles(_ article: Article) {
        if let idx = allArticles.firstIndex(where: { $0.id == article.id }) {
            allArticles[idx] = article
        }
    }
}
