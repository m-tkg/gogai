package com.mtkg.gogai.repository

import com.mtkg.gogai.model.Article
import com.mtkg.gogai.model.ArticleFilter
import com.mtkg.gogai.model.ArticleSortOrder
import com.mtkg.gogai.model.FeedCount
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.Endpoint
import kotlinx.serialization.builtins.ListSerializer

/// 記事 API（iOS ArticleRepository の移植）
class ArticleRepository(private val client: ApiClient) {

    suspend fun fetchAll(
        feedId: Int? = null,
        groupId: Int? = null,
        filter: ArticleFilter = ArticleFilter.All,
        sortOrder: ArticleSortOrder = ArticleSortOrder.PublishedAt,
        limit: Int = 1000,
        offset: Int = 0,
        includeSecret: Boolean = false,
    ): List<Article> {
        val queryItems = buildList {
            add("limit" to limit.toString())
            add("offset" to offset.toString())
            add("sortBy" to sortOrder.rawValue)
            feedId?.let { add("feedId" to it.toString()) }
            groupId?.let { add("groupId" to it.toString()) }
            when (filter) {
                ArticleFilter.All -> Unit
                ArticleFilter.Unread -> add("unreadOnly" to "true")
                // likedOnly 指定時はサーバーが sortBy を無視して liked_at 降順で返す
                ArticleFilter.Liked -> add("likedOnly" to "true")
            }
            if (includeSecret) add("includeSecret" to "true")
        }
        return client.send(Endpoint.get("/api/articles", queryItems), ListSerializer(Article.serializer()))
    }

    suspend fun fetchCounts(): List<FeedCount> =
        client.send(Endpoint.get("/api/articles/counts"), ListSerializer(FeedCount.serializer()))

    suspend fun fetch(id: Int): Article =
        client.send(Endpoint.get("/api/articles/$id"), Article.serializer())

    suspend fun markAsRead(id: Int) {
        client.sendVoid(Endpoint.post("/api/articles/$id/read"))
    }

    suspend fun markAsUnread(id: Int) {
        client.sendVoid(Endpoint.post("/api/articles/$id/unread"))
    }

    suspend fun like(id: Int) {
        client.sendVoid(Endpoint.post("/api/articles/$id/like"))
    }

    suspend fun unlike(id: Int) {
        client.sendVoid(Endpoint.post("/api/articles/$id/unlike"))
    }
}
