import Foundation

/// 全フィードの記事キャッシュ（未読バッジ計算用）を管理する値型。
/// フェッチ結果のマージ規則と個別更新を単体テスト可能な形で提供する。
/// ArticleStore はこのコレクションを単一の真実として扱い、手動の二重更新を行わない。
struct ArticleCollection: Sendable {
    private(set) var articles: [Article] = []

    var isEmpty: Bool { articles.isEmpty }

    /// フェッチ結果をマージする。
    /// - 全件フェッチ（isFullFetch=true）: 全置換
    /// - 特定フィード/グループのフェッチ: フェッチ結果に含まれるフィードの記事のみ差し替え、他は保持
    mutating func merge(_ fetched: [Article], isFullFetch: Bool) {
        if isFullFetch {
            articles = fetched
        } else {
            let fetchedFeedIds = Set(fetched.map { $0.feed_id })
            articles = articles.filter { !fetchedFeedIds.contains($0.feed_id) } + fetched
        }
    }

    /// 全記事を置き換える（refreshAllArticlesCache・キャッシュ復元用）
    mutating func replaceAll(_ newArticles: [Article]) {
        articles = newArticles
    }

    /// 全置換 + 追加分の結合。追加分のうち本体に同じ id がない記事のみ末尾に足す。
    /// （最新 N 件の全件フェッチに含まれない古いお気に入りを補完する用途）
    mutating func replaceAll(_ newArticles: [Article], appending extra: [Article]) {
        let ids = Set(newArticles.map { $0.id })
        articles = newArticles + extra.filter { !ids.contains($0.id) }
    }

    /// 同一 ID の記事を差し替える。存在しない ID は無視する（既存挙動の維持）。
    mutating func upsert(_ article: Article) {
        if let idx = articles.firstIndex(where: { $0.id == article.id }) {
            articles[idx] = article
        }
    }

    /// 全記事に変換を適用する（applyPendingReads・既読状態補正用）
    mutating func updateAll(_ transform: (Article) -> Article) {
        articles = articles.map(transform)
    }
}
