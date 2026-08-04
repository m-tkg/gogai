package com.mtkg.gogai.repository

import com.mtkg.gogai.model.Group
import com.mtkg.gogai.model.RefreshResult
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.Endpoint
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/// グループ API（iOS GroupRepository の移植）
class GroupRepository(private val client: ApiClient) {

    suspend fun fetchAll(): List<Group> =
        client.send(Endpoint.get("/api/groups"), ListSerializer(Group.serializer()))

    suspend fun create(name: String): Group {
        val body = buildJsonObject { put("name", name) }.toString()
        return client.send(Endpoint.post("/api/groups", body), Group.serializer())
    }

    suspend fun update(id: Int, name: String, isSecret: Int? = null): Group {
        val body = buildJsonObject {
            put("name", name)
            isSecret?.let { put("is_secret", it) }
        }.toString()
        return client.send(Endpoint.put("/api/groups/$id", body), Group.serializer())
    }

    suspend fun delete(id: Int) {
        client.sendVoid(Endpoint.delete("/api/groups/$id"))
    }

    suspend fun refresh(id: Int): RefreshResult =
        client.send(Endpoint.post("/api/groups/$id/refresh"), RefreshResult.serializer())

    suspend fun reorder(ids: List<Int>) {
        val body = buildJsonObject { putJsonArray("ids") { ids.forEach { add(it) } } }.toString()
        client.sendVoid(Endpoint.patch("/api/groups/reorder", body))
    }
}
