import Foundation

final class ArticleStore: ObservableObject {
    @Published var articles: [Article] = []
    /// 全フィードの記事キャッシュ（未読バッジの計算に使用）
    /// articles はフィルタ表示用なので特定フィードのみになることがあるが、
    /// allArticles は常に全体を保持して sidebar の未読カウントを正確にする
    @Published private(set) var allArticles: [Article] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var unreadOnly: Bool {
        didSet { UserDefaults.standard.set(unreadOnly, forKey: "unreadOnly") }
    }
    @Published var favoriteOnly: Bool {
        didSet { UserDefaults.standard.set(favoriteOnly, forKey: "favoriteOnly") }
    }
    @Published var sortOrder: ArticleSortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }

    private let cache: AppCache
    private var client: (any APIClientProtocol)?
    private var currentFeedId: Int?
    private var currentGroupId: Int?
    private var currentIncludeSecret: Bool = false
    /// markAsRead API 呼び出しがネットワーク障害で失敗した記事 ID セット
    /// - 対象: URLError（サーバー再起動・圏外など）のみ。4xx 等は対象外
    /// - スコープ: インメモリのみ。アプリを強制終了・再起動すると消える
    ///   （本修正の目的である「アプリを開いたままサーバーが再起動」には十分）
    /// - 次回 fetchArticles 成功時に applyPendingReads() で UI を復元し再送する
    private var pendingReadIds: Set<Int> = []
    /// 最後の fetchArticles が unreadOnly=true で実行されたかどうか
    /// refresh() での既読記事保持の判定に使用する
    /// unreadOnly=false で読み込まれた記事は「既読になった記事」と区別できないため保持しない
    private var loadedWithUnreadOnly: Bool = false
    /// 並行する fetchArticles 呼び出しで古い結果が上書きしないよう管理する世代カウンター
    private var fetchGeneration = 0
    /// isLoading を正確に管理するための実行中タスク数
    private var loadingTaskCount = 0

    init(cache: AppCache = .shared) {
        self.cache = cache
        self.unreadOnly = UserDefaults.standard.bool(forKey: "unreadOnly")
        self.favoriteOnly = UserDefaults.standard.bool(forKey: "favoriteOnly")
        let savedSort = UserDefaults.standard.string(forKey: "sortOrder") ?? ""
        self.sortOrder = ArticleSortOrder(rawValue: savedSort) ?? .publishedAt
        // 起動時にキャッシュから allArticles を読み込み、未読カウントを即座に表示する
        self.allArticles = cache.loadAllArticles()
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
                favoriteOnly: self.favoriteOnly,
                sortOrder: self.sortOrder,
                includeSecret: includeSecret
            )
            // 新しいフェッチが始まっていれば古い結果は破棄する
            guard myGeneration == fetchGeneration else { return }
            articles = fetched
            loadedWithUnreadOnly = self.unreadOnly
            // favoriteOnly は表示用のフィルターであり、
            // allArticles（未読バッジ計算用）は全記事が必要。
            // フィルターが有効な場合はフィルター済み記事で allArticles を上書きせず保持する。
            if !self.favoriteOnly {
                mergeIntoAllArticles(fetched, feedId: feedId, groupId: groupId)
            }
            // サーバーに届かなかった既読状態をローカルに復元し、バックグラウンドで再送する
            if !pendingReadIds.isEmpty {
                applyPendingReads()
                Task { await retryPendingMarkAsRead() }
            }
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

        // refresh 開始時の世代を記録し、fetch 中に外部から fetchArticles が呼ばれたか検知する
        let genBefore = fetchGeneration
        await fetchArticles(feedId: currentFeedId, groupId: currentGroupId, includeSecret: currentIncludeSecret)

        // 自分の fetchArticles 以外にも呼び出しがあった場合はその結果を尊重し保持ロジックをスキップ
        // （「全て→未読のみ」切り替えなど、ユーザー操作による最新フェッチを優先するため）
        guard fetchGeneration == genBefore + 1 else { return }

        // シークレットなしのフル更新の場合、バッジ用にシークレット記事も取得して allArticles を更新する
        // （fetchArticles が includeSecret=false だと allArticles からシークレット記事が抜けるため）
        // 注: 保持ロジックの前に実行することで、以降の既読状態補正がシークレット記事にも適用される
        if currentFeedId == nil && currentGroupId == nil && !currentIncludeSecret {
            await refreshAllArticlesCache()
            // refreshAllArticlesCache の await 中に外部 fetchArticles が呼ばれた場合は保持ロジックをスキップ
            guard fetchGeneration == genBefore + 1 else { return }
        }

        guard !previouslyReadArticles.isEmpty else { return }

        // API レスポンス遅延による未読状態の不一致を修正（fetch 結果に含まれている場合）
        let localReadIds = Set(previouslyReadArticles.map { $0.id })
        let preserveReadState: (Article) -> Article = { a in
            guard localReadIds.contains(a.id), !a.isRead else { return a }
            return a.updating(isRead: 1)
        }
        articles = articles.map(preserveReadState)
        allArticles = allArticles.map(preserveReadState)

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
        let updated = original.updating(isRead: 1, readAt: .set(nowISO))
        articles[idx] = updated
        updateAllArticles(updated)

        do {
            try await ArticleRepository(client: client).markAsRead(id: id)
            pendingReadIds.remove(id)
        } catch is URLError {
            // ネットワーク障害（サーバー再起動など）: ロールバックせず再送キューに追加
            pendingReadIds.insert(id)
        } catch {
            // 4xx など再送しても無意味なエラー: ロールバックしてエラー表示
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
            return a.updating(isRead: 1, readAt: .set(nowISO))
        }
        for a in articles { updateAllArticles(a) }

        // API calls: URLError → pending queue, others → rollback
        for original in unread {
            do {
                try await ArticleRepository(client: client).markAsRead(id: original.id)
                pendingReadIds.remove(original.id)
            } catch is URLError {
                pendingReadIds.insert(original.id)
            } catch {
                if let idx = articles.firstIndex(where: { $0.id == original.id }) {
                    articles[idx] = original
                }
                updateAllArticles(original)
            }
        }
    }

    @MainActor
    func markAsUnread(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]
        let updated = original.updating(isRead: 0, readAt: .clear)
        articles[idx] = updated
        updateAllArticles(updated)

        do {
            try await ArticleRepository(client: client).markAsUnread(id: id)
            pendingReadIds.remove(id)
        } catch is URLError {
            // ネットワーク障害: 未読操作のユーザー意図を尊重して楽観更新は維持し、
            // 未送信の既読リトライをキャンセルする（applyPendingReads で既読に戻されないように）
            pendingReadIds.remove(id)
        } catch {
            articles[idx] = original
            updateAllArticles(original)
            self.error = error
        }
    }

    @MainActor
    func favorite(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]
        let updated = original.updating(isFavorite: 1)
        articles[idx] = updated
        updateAllArticles(updated)

        do {
            try await ArticleRepository(client: client).markAsFavorite(id: id)
        } catch {
            articles[idx] = original
            updateAllArticles(original)
            self.error = error
        }
    }

    @MainActor
    func unfavorite(id: Int) async {
        guard let client else { return }
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return }
        let original = articles[idx]
        let updated = original.updating(isFavorite: 0)
        articles[idx] = updated
        updateAllArticles(updated)

        do {
            try await ArticleRepository(client: client).markAsUnfavorite(id: id)
        } catch {
            articles[idx] = original
            updateAllArticles(original)
            self.error = error
        }
    }

    /// 現在有効なフィルタ（unreadOnly / favoriteOnly）を AND で適用したとき、
    /// 指定フィードに表示対象の記事が 1 件以上あるかを返す。
    /// フィルタが何も有効でない場合は常に true。
    func hasVisibleArticle(for feedId: Int) -> Bool {
        if !unreadOnly && !favoriteOnly { return true }
        let source = allArticles.isEmpty ? articles : allArticles
        return source.contains { article in
            guard article.feed_id == feedId else { return false }
            if unreadOnly && article.isRead { return false }
            if favoriteOnly && !article.isFavorite { return false }
            return true
        }
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

    func unreadCount(excludingFeedIds feedIds: Set<Int>) -> Int {
        let source = allArticles.isEmpty ? articles : allArticles
        return source.filter { !feedIds.contains($0.feed_id) && !$0.isRead }.count
    }

    /// allArticles のキャッシュをシークレット記事を含む全件で更新する
    /// articles（表示中の記事リスト）は変更しない
    /// SidebarView の未読バッジ計算に使用する
    @MainActor
    func refreshAllArticlesCache() async {
        guard let client else { return }
        do {
            let fetched = try await ArticleRepository(client: client).fetchAll(
                unreadOnly: unreadOnly,
                sortOrder: sortOrder,
                includeSecret: true
            )
            allArticles = fetched
            cache.saveAllArticles(fetched)
        } catch {
            // ベストエフォート: キャッシュ更新失敗は無視する
        }
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
        cache.saveAllArticles(allArticles)
    }

    /// pendingReadIds に含まれる記事をローカルで既読に上書きする（fetchArticles 後に呼ぶ）
    @MainActor
    private func applyPendingReads() {
        guard !pendingReadIds.isEmpty else { return }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let apply: (Article) -> Article = { [pendingReadIds] article in
            guard pendingReadIds.contains(article.id) else { return article }
            return article.markingAsRead(at: nowISO)
        }
        articles = articles.map(apply)
        allArticles = allArticles.map(apply)
    }

    /// pendingReadIds の記事に対してサーバーへ markAsRead を再送する
    @MainActor
    private func retryPendingMarkAsRead() async {
        guard let client, !pendingReadIds.isEmpty else { return }
        let idsToRetry = pendingReadIds
        for id in idsToRetry {
            // 再送ループ中に markAsUnread が呼ばれてキューから除去された ID はスキップ
            guard pendingReadIds.contains(id) else { continue }
            do {
                try await ArticleRepository(client: client).markAsRead(id: id)
                pendingReadIds.remove(id)
            } catch {
                // 再送失敗 - 次回 fetchArticles で再試行
            }
        }
    }

    /// allArticles 内の該当記事を更新する
    /// ファイルキャッシュへの書き込みは行わない（ベストエフォート設計）。
    /// markAsRead/markAsUnread/favorite/unfavorite 等の楽観的更新はメモリのみ更新し、
    /// 次回 fetchArticles/refreshAllArticlesCache 時にキャッシュが上書きされる。
    private func updateAllArticles(_ article: Article) {
        if let idx = allArticles.firstIndex(where: { $0.id == article.id }) {
            allArticles[idx] = article
        }
    }
}
