package com.mtkg.gogai.model

import kotlinx.serialization.Serializable

@Serializable
data class Feed(
    val id: Int,
    val url: String,
    val title: String? = null,
    val favicon_url: String? = null,
    val group_id: Int? = null,
    val last_fetched_at: String? = null,
    val created_at: String,
    val display_order: Int,
)

@Serializable
data class Group(
    val id: Int,
    val name: String,
    val is_secret: Int,
    val created_at: String,
    val display_order: Int,
) {
    val isSecret: Boolean get() = is_secret == 1
}

/// フィードごとの記事集計（GET /api/articles/counts のレスポンス）。
/// サイドバーのバッジ計算に使用する。記事 0 件のフィードは含まれない。
@Serializable
data class FeedCount(
    val feed_id: Int,
    val total: Int,
    val unread: Int,
)

@Serializable
data class Settings(
    val retention_days: Int,
)

@Serializable
data class RefreshResult(
    val refreshed: Int,
    val failed: Int,
)

@Serializable
data class UpdateCheck(
    val local: String,
    val remote: String,
    val hasUpdate: Boolean,
)

@Serializable
data class Stock(
    val id: Int,
    val url: String,
    val title: String? = null,
    val source: String,
    val category_id: Int,
    val category_name: String,
    val summary: String? = null,
    val has_translation: Boolean,
    val stocked_at: String,
    val created_at: String,
) {
    /// 指定フィールドだけ差し替えた新しい Stock を返す
    fun updating(
        title: String? = null,
        categoryId: Int? = null,
        categoryName: String? = null,
        summary: FieldUpdate<String> = FieldUpdate.Keep,
        hasTranslation: Boolean? = null,
    ): Stock = copy(
        title = title ?: this.title,
        category_id = categoryId ?: category_id,
        category_name = categoryName ?: category_name,
        summary = summary.applyTo(this.summary),
        has_translation = hasTranslation ?: has_translation,
    )
}

@Serializable
data class StockCategory(
    val id: Int,
    val name: String,
    val display_order: Int,
    val created_at: String,
    val stock_count: Int,
)

@Serializable
data class StockTranslationPayload(
    val segments: String,
    val translated_at: String,
)
