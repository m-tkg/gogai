package com.mtkg.gogai.cache

import com.mtkg.gogai.model.Article
import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.FeedCount
import com.mtkg.gogai.model.Group
import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.model.StockCategory
import java.io.File
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/// アプリのローカルキャッシュ（iOS AppCache の移植）。
/// 記事・フィード・グループを cacheDir/gogai に JSON ファイルとして保存する。
class AppCache(baseDir: File) {
    private val directory = File(baseDir, "gogai")
    private val json = Json { ignoreUnknownKeys = true }

    init {
        directory.mkdirs()
    }

    fun saveAllArticles(articles: List<Article>) = save(articles, ListSerializer(Article.serializer()), "allArticles.json")
    fun loadAllArticles(): List<Article> = load(ListSerializer(Article.serializer()), "allArticles.json") ?: emptyList()

    fun saveFeedCounts(counts: List<FeedCount>) = save(counts, ListSerializer(FeedCount.serializer()), "feedCounts.json")
    fun loadFeedCounts(): List<FeedCount> = load(ListSerializer(FeedCount.serializer()), "feedCounts.json") ?: emptyList()

    fun saveFeeds(feeds: List<Feed>) = save(feeds, ListSerializer(Feed.serializer()), "feeds.json")
    fun loadFeeds(): List<Feed> = load(ListSerializer(Feed.serializer()), "feeds.json") ?: emptyList()

    fun saveGroups(groups: List<Group>) = save(groups, ListSerializer(Group.serializer()), "groups.json")
    fun loadGroups(): List<Group> = load(ListSerializer(Group.serializer()), "groups.json") ?: emptyList()

    fun saveStocks(stocks: List<Stock>) = save(stocks, ListSerializer(Stock.serializer()), "stocks.json")
    fun loadStocks(): List<Stock> = load(ListSerializer(Stock.serializer()), "stocks.json") ?: emptyList()

    fun saveStockCategories(categories: List<StockCategory>) =
        save(categories, ListSerializer(StockCategory.serializer()), "stockCategories.json")
    fun loadStockCategories(): List<StockCategory> =
        load(ListSerializer(StockCategory.serializer()), "stockCategories.json") ?: emptyList()

    val totalSize: Long
        get() = directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    fun clearAll() {
        directory.deleteRecursively()
        directory.mkdirs()
    }

    private fun <T> save(value: T, serializer: KSerializer<T>, filename: String) {
        runCatching {
            // 書き込み途中のクラッシュで壊れたファイルを残さないよう一時ファイル経由で置き換える
            val tmp = File(directory, "$filename.tmp")
            tmp.writeText(json.encodeToString(serializer, value))
            tmp.renameTo(File(directory, filename))
        }
    }

    private fun <T> load(serializer: KSerializer<T>, filename: String): T? {
        val file = File(directory, filename)
        if (!file.exists()) return null
        return runCatching { json.decodeFromString(serializer, file.readText()) }.getOrNull()
    }
}
