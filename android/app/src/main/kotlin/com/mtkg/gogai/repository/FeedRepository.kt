package com.mtkg.gogai.repository

import com.mtkg.gogai.model.Feed
import com.mtkg.gogai.model.FieldUpdate
import com.mtkg.gogai.model.RefreshResult
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.Endpoint
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/// フィード API（iOS FeedRepository の移植）
class FeedRepository(private val client: ApiClient) {

    suspend fun fetchAll(): List<Feed> =
        client.send(Endpoint.get("/api/feeds"), ListSerializer(Feed.serializer()))

    suspend fun create(url: String, groupId: Int? = null): Feed {
        val body = buildJsonObject {
            put("url", url)
            groupId?.let { put("groupId", it) }
        }.toString()
        return client.send(Endpoint.post("/api/feeds", body), Feed.serializer())
    }

    // Why: iOS の groupId は Int?? （外側 Optional = キー送信有無、内側 Optional = 値 or 明示 null）
    // に相当する。Kotlin では FieldUpdate で表現する: Keep はキー省略、Clear は "groupId": null、
    // Set(v) は値を送信する。
    suspend fun update(id: Int, title: String? = null, groupId: FieldUpdate<Int> = FieldUpdate.Keep): Feed {
        val body = buildJsonObject {
            title?.let { put("title", it) }
            when (groupId) {
                is FieldUpdate.Keep -> Unit
                is FieldUpdate.Clear -> put("groupId", JsonNull)
                is FieldUpdate.Set -> put("groupId", groupId.value)
            }
        }.toString()
        return client.send(Endpoint.put("/api/feeds/$id", body), Feed.serializer())
    }

    suspend fun delete(id: Int) {
        client.sendVoid(Endpoint.delete("/api/feeds/$id"))
    }

    suspend fun refresh(id: Int): RefreshResult =
        client.send(Endpoint.post("/api/feeds/$id/refresh"), RefreshResult.serializer())

    suspend fun refreshAll(): RefreshResult =
        client.send(Endpoint.post("/api/feeds/refresh-all"), RefreshResult.serializer())

    suspend fun reorder(ids: List<Int>) {
        val body = buildJsonObject { putJsonArray("ids") { ids.forEach { add(it) } } }.toString()
        client.sendVoid(Endpoint.patch("/api/feeds/reorder", body))
    }
}
