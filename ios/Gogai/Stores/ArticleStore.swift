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
    @Published var unreadOnly: Bool {
        didSet { UserDefaults.standard.set(unreadOnly, forKey: DefaultsKeys.unreadOnly) }
    }
    @Published var favoriteOnly: Bool {
        didSet { UserDefaults.standard.set(favoriteOnly, forKey: DefaultsKeys.favoriteOnly) }
    }
    @Published var sortOrder: ArticleSortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKeys.sortOrder) }
    }

    /// 互換 API: 旧 allArticles プロパティ（コレクションの内容を公開する）
    var allArticles: [Article] { allCollection.articles }

    private let cache: AppCache
    private var client: (any APIClientProtocol)?
    /// お気に入り成功時に呼ばれるコールバック(ストック連携用)。
    /// ArticleStore は StockStore を知らず、GogaiApp が configure 時に注入する。
    private var onFavoriteSucceeded: ((Article) -> Void)?
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
        self.unreadOnly = UserDefaults.standard.bool(forKey: DefaultsKeys.unreadOnly)
        self.favoriteOnly = UserDefaults.standard.bool(forKey: DefaultsKeys.favoriteOnly)
        let savedSort = UserDefaults.standard.string(forKey: DefaultsKeys.sortOrder) ?? ""
        self.sortOrder = ArticleSortOrder(rawValue: savedSort) ?? .publishedAt
        // 起動時にキャッシュから全記事を読み込み、未読カウントを即座に表示する
        self.allCollection.replaceAll(cache.loadAllArticles())
        self.feedCounts = Self.indexed(cache.loadFeedCounts())
    }

    private static func indexed(_ counts: [FeedCount]) -> [Int: FeedCount] {
        Dictionary(counts.map { ($0.feed_id, $0) }, uniquingKeysWith: { _, new in new })
    }

    func configure(with client: any APIClientProtocol, onFavoriteSucceeded: ((Article) -> Void)? = nil) {
        self.client = client
        self.onFavoriteSucceeded = onFavoriteSucceeded
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
            // コレクション（未読バッジ・サイドバー表示判定用）は全記事が必要。
            // unreadOnly / favoriteOnly のフィルターが有効なフェッチ結果は一部の記事しか
            // 含まないため、これで上書きするとキャッシュが汚染される
            // （例: unreadOnly のフェッチで既読のお気に入り記事が失われ、お気に入り表示時に
            //  該当フィードがサイドバーから消える）。フィルターなしの全件フェッチ時のみ更新する。
            if !self.unreadOnly && !self.favoriteOnly {
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
        // refresh 前に既読になっていた記事を保存する
        // unreadOnly=true かつ前回フェッチも unreadOnly=true だった場合のみ保存する
        // （unreadOnly=false で読み込まれた記事は既読・未読が混在しており、
        //   「このセッションで読んだ記事」と区別できないため保持しない）
        let previouslyReadArticles = loadedWithUnreadOnly ? articles.filter { $0.isRead } : []

        // refresh 開始時の世代を記録し、fetch 中に外部から fetchArticles が呼ばれたか検知する
        let genBefore = fetchGeneration
        await fetchArticles(feedId: currentFeedId, groupId: currentGroupId, includeSecret: currentIncludeSecret)

        // バッジ用のサーバー集計は表示中フィードに関わらずグローバルに更新する
        // （特定フィード表示中でも他フィードの新着がバッジに反映されるように）
        await refreshCounts()

        // 自分の fetchArticles 以外にも呼び出しがあった場合はその結果を尊重し保持ロジックをスキップ
        // （「全て→未読のみ」切り替えなど、ユーザー操作による最新フェッチを優先するため）
        guard fetchGeneration == genBefore + 1 else { return }

        guard !previouslyReadArticles.isEmpty else { return }

        // API レスポンス遅延による未読状態の不一致を修正（fetch 結果に含まれている場合）
        let localReadIds = Set(previouslyReadArticles.map { $0.id })
        let preserveReadState: (Article) -> Article = { a in
            guard localReadIds.contains(a.id), !a.isRead else { return a }
            return a.updating(isRead: 1)
        }
        articles = articles.map(preserveReadState)
        allCollection.updateAll(preserveReadState)

        // unreadOnly: true の場合、fetch 結果に含まれなかった既読記事をリストに保持する
        // （このセッションで読んだ記事が自動 refresh で消えないようにするため）
        // コレクションは未読バッジ計算用のため、既読になった記事は追加不要
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

    /// 既読⇄未読を記事の現在状態に応じて切り替える（View 側の分岐重複を防ぐ）
    @MainActor
    func toggleRead(_ article: Article) async {
        if article.isRead {
            await markAsUnread(id: article.id)
        } else {
            await markAsRead(id: article.id)
        }
    }

    /// お気に入り⇄解除を記事の現在状態に応じて切り替える
    @MainActor
    func toggleFavorite(_ article: Article) async {
        if article.isFavorite {
            await unfavorite(id: article.id)
        } else {
            await favorite(id: article.id)
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

    @MainActor
    func favorite(id: Int) async {
        guard let client else { return }
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(isFavorite: 1) },
            apiCall: { try await ArticleRepository(client: client).markAsFavorite(id: id) },
            onURLError: .rollback
        )
        // ロールバックされていなければ(=お気に入り成功)ストック連携コールバックを発火する
        if let article = articles.first(where: { $0.id == id }), article.isFavorite {
            onFavoriteSucceeded?(article)
        }
    }

    @MainActor
    func unfavorite(id: Int) async {
        guard let client else { return }
        await optimisticUpdate(
            id: id,
            transform: { $0.updating(isFavorite: 0) },
            apiCall: { try await ArticleRepository(client: client).markAsUnfavorite(id: id) },
            onURLError: .rollback
        )
    }

    // MARK: - バッジ件数・表示判定（現在のフィルタに連動）

    /// バッジ計算・表示判定に使う記事ソース。
    /// 全フィードキャッシュ（コレクション）を優先し、空のときだけ表示中リストにフォールバックする。
    private var badgeSource: [Article] {
        allCollection.isEmpty ? articles : allCollection.articles
    }

    /// 現在のフィルタ（全て / 未読のみ / お気に入り）に記事が合致するか
    private func matchesCurrentFilter(_ article: Article) -> Bool {
        if unreadOnly && article.isRead { return false }
        if favoriteOnly && !article.isFavorite { return false }
        return true
    }

    /// サーバー集計をバッジ計算に使えるか。
    /// 未取得（空）のときはコレクション計算にフォールバックする。
    /// unreadOnly && favoriteOnly の AND 条件は 3 値の集計では表現できないため対象外
    /// （UI からは到達不能な組み合わせだが防御的にフォールバックする）。
    private var canUseFeedCounts: Bool {
        !feedCounts.isEmpty && !(unreadOnly && favoriteOnly)
    }

    /// 現在のフィルタに対応する集計値。「全て」= total、「未読のみ」= unread、「お気に入り」= favorite
    private func filteredCount(_ count: FeedCount) -> Int {
        if unreadOnly { return count.unread }
        if favoriteOnly { return count.favorite }
        return count.total
    }

    /// 現在有効なフィルタ（unreadOnly / favoriteOnly）を AND で適用したとき、
    /// 指定フィードに表示対象の記事が 1 件以上あるかを返す。
    /// フィルタが何も有効でない場合は常に true。
    func hasVisibleArticle(for feedId: Int) -> Bool {
        if !unreadOnly && !favoriteOnly { return true }
        if canUseFeedCounts {
            return feedCounts[feedId].map { filteredCount($0) > 0 } ?? false
        }
        return badgeSource.contains { $0.feed_id == feedId && matchesCurrentFilter($0) }
    }

    /// フィードのバッジ件数。「全て」=全記事数、「未読のみ」=未読数、「お気に入り」=お気に入り数
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

    /// サーバー集計（フィードごとの total/unread/favorite）を取得してバッジ計算を最新化する。
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
                favorite: count.favorite
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
        /// 通常エラーと同様にロールバックする（favorite / unfavorite）
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
            // 既読系の成功時のみ pending を解消する（favorite 系は既読リトライに関与しない）
            if onURLError != .rollback {
                pendingReadIds.remove(id)
            }
        } catch let error as URLError {
            switch onURLError {
            case .enqueuePendingRead:
                pendingReadIds.insert(id)
            case .cancelPendingRead:
                pendingReadIds.remove(id)
            case .rollback:
                mutateBoth(id: id) { _ in original }
                self.error = error
            }
        } catch {
            mutateBoth(id: id) { _ in original }
            self.error = error
        }
    }

    /// articles とコレクションの該当記事を同一の変換で更新する（同期漏れを構造的に防ぐ）。
    /// feedCounts にも既読/お気に入りの差分を反映する（ロールバックは逆変換で自動的に打ち消される）。
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
        let favoriteDelta = (updated.isFavorite ? 1 : 0) - (original.isFavorite ? 1 : 0)
        guard unreadDelta != 0 || favoriteDelta != 0 else { return }
        feedCounts[original.feed_id] = FeedCount(
            feed_id: count.feed_id,
            total: count.total,
            unread: max(0, count.unread + unreadDelta),
            favorite: max(0, count.favorite + favoriteDelta)
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
