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
) {
    val isRead: Boolean get() = is_read == 1

    /// 指定フィールドだけ差し替えた新しい Article を返す
    fun updating(isRead: Int? = null, readAt: FieldUpdate<String> = FieldUpdate.Keep): Article =
        copy(is_read = isRead ?: is_read, read_at = readAt.applyTo(read_at))

    /// 既読状態にした新しい Article を返す
    fun markingAsRead(at: String): Article {
        if (isRead) return this
        return updating(isRead = 1, readAt = FieldUpdate.Set(read_at ?: at))
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
