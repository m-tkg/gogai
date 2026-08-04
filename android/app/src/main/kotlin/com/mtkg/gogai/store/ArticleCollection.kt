package com.mtkg.gogai.store

import com.mtkg.gogai.model.Article

/// 全フィードの記事キャッシュ（未読バッジ計算用）を管理するクラス（iOS ArticleCollection の移植）。
/// フェッチ結果のマージ規則と個別更新を単体テスト可能な形で提供する。
/// ArticleStore はこのコレクションを単一の真実として扱い、手動の二重更新を行わない。
class ArticleCollection {
    var articles: List<Article> = emptyList()
        private set

    val isEmpty: Boolean get() = articles.isEmpty()

    /// フェッチ結果をマージする。
    /// - 全件フェッチ（isFullFetch=true）: 全置換
    /// - 特定フィード/グループのフェッチ: フェッチ結果に含まれるフィードの記事のみ差し替え、他は保持
    fun merge(fetched: List<Article>, isFullFetch: Boolean) {
        articles = if (isFullFetch) {
            fetched
        } else {
            val fetchedFeedIds = fetched.map { it.feed_id }.toSet()
            articles.filter { it.feed_id !in fetchedFeedIds } + fetched
        }
    }

    /// 全記事を置き換える（キャッシュ復元用）
    fun replaceAll(newArticles: List<Article>) {
        articles = newArticles
    }

    /// 同一 ID の記事を差し替える。存在しない ID は無視する（既存挙動の維持）。
    fun upsert(article: Article) {
        val idx = articles.indexOfFirst { it.id == article.id }
        if (idx >= 0) {
            articles = articles.toMutableList().also { it[idx] = article }
        }
    }

    /// 全記事に変換を適用する（applyPendingReads・既読状態補正用）
    fun updateAll(transform: (Article) -> Article) {
        articles = articles.map(transform)
    }
}
