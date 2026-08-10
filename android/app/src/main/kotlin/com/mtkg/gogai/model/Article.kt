package com.mtkg.gogai.model

import kotlinx.serialization.Serializable

// フィールド名はバックエンド API の snake_case をそのまま使う（iOS 実装と同じ方針）
@Serializable
data class Article(
    val id: Int,
    val feed_id: Int,
    val guid: String,
    val title: String? = null,
    val link: String? = null,
    val summary: String? = null,
    val content: String? = null,
    val published_at: String? = null,
    val is_read: Int,
    val created_at: String,
    val read_at: String? = null,
    /// ユーザーが「好み」と表明した日時。null = 未 like。
    /// 外部のキュレーション AI へ渡すシグナルで、既読とは独立した軸。
    val liked_at: String? = null,
    /// liked_at の対になる負のシグナル。null = 未 dislike。liked_at とは排他。
    val disliked_at: String? = null,
) {
    val isRead: Boolean get() = is_read == 1
    val isLiked: Boolean get() = liked_at != null
    val isDisliked: Boolean get() = disliked_at != null

    /// 指定フィールドだけ差し替えた新しい Article を返す
    fun updating(
        isRead: Int? = null,
        readAt: FieldUpdate<String> = FieldUpdate.Keep,
        likedAt: FieldUpdate<String> = FieldUpdate.Keep,
        dislikedAt: FieldUpdate<String> = FieldUpdate.Keep,
    ): Article =
        copy(
            is_read = isRead ?: is_read,
            read_at = readAt.applyTo(read_at),
            liked_at = likedAt.applyTo(liked_at),
            disliked_at = dislikedAt.applyTo(disliked_at),
        )

    /// 既読状態にした新しい Article を返す
    fun markingAsRead(at: String): Article {
        if (isRead) return this
        return updating(isRead = 1, readAt = FieldUpdate.Set(read_at ?: at))
    }
}

/// 記事一覧のフィルター（フィードページ・記事一覧ページのフッターで排他選択する。iOS ArticleFilter の移植）
enum class ArticleFilter(val rawValue: String) {
    All("all"),
    Unread("unread"),
    Liked("liked"),
    Disliked("disliked");

    /// サーバーから全件を取得するフィルターかどうか。
    /// false のフィルターは部分フェッチなので、全記事キャッシュ（ArticleCollection）を上書きしない。
    val isFullFetch: Boolean get() = this == All

    companion object {
        fun fromRawValue(raw: String?): ArticleFilter? = entries.firstOrNull { it.rawValue == raw }
    }
}

enum class ArticleSortOrder(val rawValue: String) {
    PublishedAt("published_at"),
    ReadAt("read_at");

    val label: String
        get() = when (this) {
            PublishedAt -> "配信日順"
            ReadAt -> "既読日時順"
        }

    companion object {
        fun fromRawValue(raw: String?): ArticleSortOrder? = entries.firstOrNull { it.rawValue == raw }
    }
}
