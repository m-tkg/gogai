import Foundation

final class ArticleStore: ObservableObject {
    @Published var articles: [Article] = []
    /// 全フィードの記事キャッシュ（未読バッジの計算に使用）。
    /// articles はフィルタ表示用なので特定フィードのみになることがあるが、
    /// collection は常に全体を保持して sidebar の未読カウントを正確にする。
    /// 更新は必ず mutateBoth / merge 経由で行い、articles との手動二重更新をしない。
    @Published private(set) var allCollection = ArticleCollection()
    /// フィードごとのサーバー集計（GET /api/articles/counts）。バッジ計算の第一ソース。
    /// 空（未取得）のときは allCollection ベースの計算にフォールバックする。
    @Published private(set) var feedCounts: [Int: FeedCount] = [:]
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var filter: ArticleFilter {
        didSet { UserDefaults.standard.set(filter.rawValue, forKey: DefaultsKeys.articleFilter) }
    }
    @Published var sortOrder: ArticleSortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKeys.sortOrder) }
    }

    /// 互換 API: 旧 allArticles プロパティ（コレクションの内容を公開する）
    var allArticles: [Article] { allCollection.articles }

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
    /// 最後の fetchArticles を実行したときのフィルター
    /// refresh() での「フィルターから外れた記事」の保持判定に使用する
    /// .all で読み込まれた記事は「このセッションで状態が変わった記事」と区別できないため保持しない
    private var loadedWithFilter: ArticleFilter = .all
    /// 並行する fetchArticles 呼び出しで古い結果が上書きしないよう管理する世代カウンター
    private var fetchGeneration = 0
    /// isLoading を正確に管理するための実行中タスク数
    private var loadingTaskCount = 0

    init(cache: AppCache = .shared) {
        self.cache = cache
        // 旧バージョンの unreadOnly（Bool）しか無いユーザーはそこから移行する
        if let saved = UserDefaults.standard.string(forKey: DefaultsKeys.articleFilter),
           let restored = ArticleFilter(rawValue: saved) {
            self.filter = restored
        } else {
            self.filter = UserDefaults.standard.bool(forKey: DefaultsKeys.unreadOnly) ? .unread : .all
        }
        let savedSort = UserDefaults.standard.string(forKey: DefaultsKeys.sortOrder) ?? ""
        self.sortOrder = ArticleSortOrder(rawValue: savedSort) ?? .publishedAt
        // 起動時にキャッシュから全記事を読み込み、未読カウントを即座に表示する
        self.allCollection.replaceAll(cache.loadAllArticles())
        self.feedCounts = Self.indexed(cache.loadFeedCounts())
    }

    private static func indexed(_ counts: [FeedCount]) -> [Int: FeedCount] {
        Dictionary(counts.map { ($0.feed_id, $0) }, uniquingKeysWith: { _, new in new })
    }

    func configure(with client: any APIClientProtocol) {
        self.client = client
    }

    @MainActor
    func fetchArticles(feedId: Int? = nil, groupId: Int? = nil, filter: ArticleFilter? = nil, includeSecret: Bool = false) async {
        guard let client else { return }
        currentFeedId = feedId
        currentGroupId = groupId
        currentIncludeSecret = includeSecret
        if let filter { self.filter = filter }
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
                filter: self.filter,
                sortOrder: self.sortOrder,
                includeSecret: includeSecret
            )
            // 新しいフェッチが始まっていれば古い結果は破棄する
            guard myGeneration == fetchGeneration else { return }
            articles = fetched
            loadedWithFilter = self.filter
            // コレクション（未読バッジ・サイドバー表示判定用）は全記事が必要。
            // フィルターが有効なフェッチ結果は一部の記事しか含まないため、
            // これで上書きするとキャッシュが汚染される。フィルターなしの全件フェッチ時のみ更新する。
            if self.filter.isFullFetch {
                allCollection.merge(fetched, isFullFetch: feedId == nil && groupId == nil)
                cache.saveAllArticles(allCollection.articles)
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
        // refresh 前に「フィルターから外れた記事」を保存する
        // （未読のみ表示中に既読にした記事 / like 表示中に like を外した記事）
        // .all で読み込まれた記事は混在しており「このセッションで操作した記事」と区別できないため保持しない
        let previouslyVisibleArticles = loadedWithFilter.isFullFetch ? [] : articles.filter { !matchesCurrentFilter($0) }

        // refresh 開始時の世代を記録し、fetch 中に外部から fetchArticles が呼ばれたか検知する
        let genBefore = fetchGeneration
        await fetchArticles(feedId: currentFeedId, groupId: currentGroupId, includeSecret: currentIncludeSecret)

        // バッジ用のサーバー集計は表示中フィードに関わらずグローバルに更新する
        // （特定フィード表示中でも他フィードの新着がバッジに反映されるように）
        await refreshCounts()

        // 自分の fetchArticles 以外にも呼び出しがあった場合はその結果を尊重し保持ロジックをスキップ
        // （「全て→未読のみ」切り替えなど、ユーザー操作による最新フェッチを優先するため）
        guard fetchGeneration == genBefore + 1 else { return }

        guard !previouslyVisibleArticles.isEmpty else { return }

        // API レスポンス遅延による未読状態の不一致を修正（fetch 結果に含まれている場合）
        // like は解除がサーバーへ即時反映されるため、既読のみを対象にする
        if filter == .unread {
            let localReadIds = Set(previouslyVisibleArticles.filter { $0.isRead }.map { $0.id })
            let preserveReadState: (Article) -> Article = { a in
                guard localReadIds.contains(a.id), !a.isRead else { return a }
                return a.updating(isRead: 1)
            }
            articles = articles.map(preserveReadState)
            allCollection.updateAll(preserveReadState)
        }

        // fetch 結果に含まれなかった記事（既読にした / like を外した）をリストに保持する
        // （このセッションで操作した記事が自動 refresh で消えないようにするため）
        // コレクションは未読バッジ計算用のため、フィルターから外れた記事は追加不要
        let newIds = Set(articles.map { $0.id })
        let toPreserve = previouslyVisibleArticles.filter { !newIds.contains($0.id) }
        guard !toPreserve.isEmpty else { return }
        articles = (articles + toPreserve).sorted(by: sortComparator)
    }

    /// 現在のフィルター・ソート順に対応する並び替え規則
    private var sortComparator: (Article, Article) -> Bool {
        // 評価の一覧はサーバーが評価日時の降順で返すため、ローカル保持分も同じ規則で並べる
        if filter == .liked {
            return { ($0.liked_at ?? "") > ($1.liked_at ?? "") }
        }
        if filter == .disliked {
            return { ($0.disliked_at ?? "") > ($1.disliked_at ?? "") }
        }
        switch sortOrder {
        case .publishedAt:
            return { ($0.published_at ?? $0.created_at) > ($1.published_at ?? $1.created_at) }
        case .readAt:
            return { ($0.read_at ?? $0.published_at ?? $0.created_at) > ($1.read_at ?? $1.published_at ?? $1.created_at) }
        }
    }

    /// 既読⇄未読を記事の現在状態に応じて切り替える（View 側の分岐重複を防ぐ）
    @MainActor
    func toggleRead(_ article: Article) async {
        if article.isRead {
            await markAsUnread(id: article.id)
        } else {
            await markAsRead(id: article.id)
        }
    }

    @MainActor
    func markAsRead(id: Int) async {
        guard let client else { return }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(isRead: 1, readAt: .set(nowISO)) },
            apiCall: { try await ArticleRepository(client: client).markAsRead(id: id) },
            onURLError: .enqueuePendingRead
        )
    }

    @MainActor
    func markAllAsRead() async {
        let unread = articles.filter { !$0.isRead }
        guard !unread.isEmpty, let client else { return }

        // Optimistic update（mutateBoth 経由で articles / コレクション / feedCounts を同期）
        let nowISO = ISO8601DateFormatter().string(from: Date())
        for article in unread {
            mutateBoth(id: article.id) { $0.updating(isRead: 1, readAt: .set(nowISO)) }
        }

        // API calls: URLError → pending queue, others → rollback
        for original in unread {
            do {
                try await ArticleRepository(client: client).markAsRead(id: original.id)
                pendingReadIds.remove(original.id)
            } catch is URLError {
                pendingReadIds.insert(original.id)
            } catch {
                mutateBoth(id: original.id) { _ in original }
            }
        }

        // サーバー集計と突き合わせてバッジを確定させる（失敗時はローカル差分を維持）
        await refreshCounts()
    }

    @MainActor
    func markAsUnread(id: Int) async {
        guard let client else { return }
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(isRead: 0, readAt: .clear) },
            apiCall: { try await ArticleRepository(client: client).markAsUnread(id: id) },
            onURLError: .cancelPendingRead
        )
    }

    // MARK: - like（キュレーター向けの好みシグナル。既読とは独立した軸）

    /// like ⇄ 未 like を記事の現在状態に応じて切り替える（View 側の分岐重複を防ぐ）
    @MainActor
    func toggleLike(_ article: Article) async {
        if article.isLiked {
            await unlike(id: article.id)
        } else {
            await like(id: article.id)
        }
    }

    @MainActor
    func like(id: Int) async {
        guard let client else { return }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        await optimisticUpdate(
            id: id,
            // サーバーが排他にするので楽観更新も同じ規則で dislike を落とす
            transform: { $0.updating(likedAt: .set(nowISO), dislikedAt: .clear) },
            apiCall: { try await ArticleRepository(client: client).like(id: id) },
            onURLError: .rollback
        )
    }

    @MainActor
    func unlike(id: Int) async {
        guard let client else { return }
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(likedAt: .clear) },
            apiCall: { try await ArticleRepository(client: client).unlike(id: id) },
            onURLError: .rollback
        )
    }

    /// dislike ⇄ 未 dislike を記事の現在状態に応じて切り替える
    @MainActor
    func toggleDislike(_ article: Article) async {
        if article.isDisliked {
            await undislike(id: article.id)
        } else {
            await dislike(id: article.id)
        }
    }

    @MainActor
    func dislike(id: Int) async {
        guard let client else { return }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(likedAt: .clear, dislikedAt: .set(nowISO)) },
            apiCall: { try await ArticleRepository(client: client).dislike(id: id) },
            onURLError: .rollback
        )
    }

    @MainActor
    func undislike(id: Int) async {
        guard let client else { return }
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(dislikedAt: .clear) },
            apiCall: { try await ArticleRepository(client: client).undislike(id: id) },
            onURLError: .rollback
        )
    }

    // MARK: - バッジ件数・表示判定（現在のフィルタに連動）

    /// バッジ計算・表示判定に使う記事ソース。
    /// 全フィードキャッシュ（コレクション）を優先し、空のときだけ表示中リストにフォールバックする。
    private var badgeSource: [Article] {
        allCollection.isEmpty ? articles : allCollection.articles
    }

    /// 現在のフィルタ（全て / 未読のみ / like / dislike）に記事が合致するか
    private func matchesCurrentFilter(_ article: Article) -> Bool {
        switch filter {
        case .all: return true
        case .unread: return !article.isRead
        case .liked: return article.isLiked
        case .disliked: return article.isDisliked
        }
    }

    /// サーバー集計をバッジ計算に使えるか。未取得（空）のときはコレクション計算にフォールバックする。
    private var canUseFeedCounts: Bool {
        !feedCounts.isEmpty
    }

    /// 現在のフィルタに対応する集計値。「全て」= total、「未読のみ」= unread、
    /// 「like」= liked、「dislike」= disliked
    private func filteredCount(_ count: FeedCount) -> Int {
        switch filter {
        case .all: return count.total
        case .unread: return count.unread
        case .liked: return count.liked
        case .disliked: return count.disliked
        }
    }

    /// 現在有効なフィルタを適用したとき、
    /// 指定フィードに表示対象の記事が 1 件以上あるかを返す。
    /// フィルタが何も有効でない場合は常に true。
    func hasVisibleArticle(for feedId: Int) -> Bool {
        if filter.isFullFetch { return true }
        if canUseFeedCounts {
            return feedCounts[feedId].map { filteredCount($0) > 0 } ?? false
        }
        return badgeSource.contains { $0.feed_id == feedId && matchesCurrentFilter($0) }
    }

    /// フィードのバッジ件数。「全て」=全記事数、「未読のみ」=未読数、「like」=like 数
    func badgeCount(for feedId: Int?) -> Int {
        if canUseFeedCounts {
            guard let feedId else { return feedCounts.values.reduce(0) { $0 + filteredCount($1) } }
            return feedCounts[feedId].map(filteredCount) ?? 0
        }
        let filtered = feedId.map { fid in badgeSource.filter { $0.feed_id == fid } } ?? badgeSource
        return filtered.filter(matchesCurrentFilter).count
    }

    /// グループ（所属フィード群）のバッジ件数
    func badgeCount(forGroupFeedIds feedIds: [Int]) -> Int {
        if canUseFeedCounts {
            return feedIds.reduce(0) { $0 + (feedCounts[$1].map(filteredCount) ?? 0) }
        }
        let feedIdSet = Set(feedIds)
        return badgeSource.filter { feedIdSet.contains($0.feed_id) && matchesCurrentFilter($0) }.count
    }

    /// 「すべての記事」のバッジ件数（シークレットフィード除外用）
    func badgeCount(excludingFeedIds feedIds: Set<Int>) -> Int {
        if canUseFeedCounts {
            return feedCounts.values.reduce(0) { $0 + (feedIds.contains($1.feed_id) ? 0 : filteredCount($1)) }
        }
        return badgeSource.filter { !feedIds.contains($0.feed_id) && matchesCurrentFilter($0) }.count
    }

    /// サーバー集計（フィードごとの total/unread）を取得してバッジ計算を最新化する。
    /// ベストエフォート: 失敗時は前回値（起動時はディスクキャッシュ復元値）を維持し error を立てない。
    @MainActor
    func refreshCounts() async {
        guard let client else { return }
        guard let fetched = try? await ArticleRepository(client: client).fetchCounts() else { return }
        feedCounts = Self.indexed(fetched)
        // pending（サーバーに届いていない既読）はサーバー集計に未反映のため減算して補正する
        for id in pendingReadIds {
            guard let article = allCollection.articles.first(where: { $0.id == id })
                    ?? articles.first(where: { $0.id == id }) else { continue }
            guard let count = feedCounts[article.feed_id] else { continue }
            feedCounts[article.feed_id] = FeedCount(
                feed_id: count.feed_id,
                total: count.total,
                unread: max(0, count.unread - 1),
                liked: count.liked,
                disliked: count.disliked
            )
        }
        cache.saveFeedCounts(fetched)
    }

    // MARK: - Private

    /// URLError（ネットワーク障害）発生時の振る舞い
    private enum URLErrorPolicy: Equatable {
        /// 楽観更新を維持し、既読リトライキューに積む（markAsRead）
        case enqueuePendingRead
        /// 楽観更新を維持し、既読リトライキューから取り除く（markAsUnread）
        case cancelPendingRead
        /// 楽観更新を取り消す。既読キューには触れない（like / unlike）
        case rollback
    }

    /// 楽観的更新の唯一の経路。
    /// articles とコレクションを同一の変換で同期更新し、API 失敗時はロールバックする。
    @MainActor
    private func optimisticUpdate(
        id: Int,
        transform: (Article) -> Article,
        apiCall: () async throws -> Void,
        onURLError: URLErrorPolicy
    ) async {
        guard let original = mutateBoth(id: id, transform) else { return }

        do {
            try await apiCall()
            // like 系は既読キューと無関係なので、成功しても既読の再送予定を消さない
            if onURLError != .rollback { pendingReadIds.remove(id) }
        } catch is URLError {
            switch onURLError {
            case .enqueuePendingRead:
                pendingReadIds.insert(id)
            case .cancelPendingRead:
                pendingReadIds.remove(id)
            case .rollback:
                mutateBoth(id: id) { _ in original }
            }
        } catch {
            mutateBoth(id: id) { _ in original }
            self.error = error
        }
    }

    /// articles とコレクションの該当記事を同一の変換で更新する（同期漏れを構造的に防ぐ）。
    /// feedCounts にも既読状態の差分を反映する（ロールバックは逆変換で自動的に打ち消される）。
    /// - Returns: 変換前の記事（articles に存在しない場合は nil で何もしない）
    @MainActor
    @discardableResult
    private func mutateBoth(id: Int, _ transform: (Article) -> Article) -> Article? {
        guard let idx = articles.firstIndex(where: { $0.id == id }) else { return nil }
        let original = articles[idx]
        let updated = transform(original)
        articles[idx] = updated
        allCollection.upsert(updated)
        applyCountsDelta(from: original, to: updated)
        return original
    }

    /// 記事の変換前後の状態差分を feedCounts に反映する。
    /// counts に無い feed_id は無視する（サーバー集計との整合のため勝手に行を作らない）。
    @MainActor
    private func applyCountsDelta(from original: Article, to updated: Article) {
        guard let count = feedCounts[original.feed_id] else { return }
        let unreadDelta = (updated.isRead ? 0 : 1) - (original.isRead ? 0 : 1)
        let likedDelta = (updated.isLiked ? 1 : 0) - (original.isLiked ? 1 : 0)
        let dislikedDelta = (updated.isDisliked ? 1 : 0) - (original.isDisliked ? 1 : 0)
        guard unreadDelta != 0 || likedDelta != 0 || dislikedDelta != 0 else { return }
        feedCounts[original.feed_id] = FeedCount(
            feed_id: count.feed_id,
            total: count.total,
            unread: max(0, count.unread + unreadDelta),
            liked: max(0, count.liked + likedDelta),
            disliked: max(0, count.disliked + dislikedDelta)
        )
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
        allCollection.updateAll(apply)
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
}
