package com.mtkg.gogai.repository

import com.mtkg.gogai.model.Stock
import com.mtkg.gogai.model.StockCategory
import com.mtkg.gogai.model.StockTranslationPayload
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.Endpoint
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

@Serializable
private data class StockLookupResponse(val stock: Stock? = null)

/// ストック API（iOS StockRepository の移植）
class StockRepository(private val client: ApiClient) {

    suspend fun fetchAll(categoryId: Int? = null): List<Stock> {
        val queryItems = categoryId?.let { listOf("category_id" to it.toString()) } ?: emptyList()
        return client.send(Endpoint.get("/api/stocks", queryItems), ListSerializer(Stock.serializer()))
    }

    suspend fun create(url: String, title: String? = null, source: String? = null, category: String? = null): Stock {
        val body = buildJsonObject {
            put("url", url)
            title?.let { put("title", it) }
            source?.let { put("source", it) }
            category?.let { put("category", it) }
        }.toString()
        return client.send(Endpoint.post("/api/stocks", body), Stock.serializer())
    }

    suspend fun update(id: Int, title: String, category: String): Stock {
        val body = buildJsonObject {
            put("title", title)
            put("category", category)
        }.toString()
        return client.send(Endpoint.put("/api/stocks/$id", body), Stock.serializer())
    }

    suspend fun delete(id: Int) {
        client.sendVoid(Endpoint.delete("/api/stocks/$id"))
    }

    suspend fun saveSummary(id: Int, summary: String) {
        val body = buildJsonObject { put("summary", summary) }.toString()
        client.sendVoid(Endpoint.put("/api/stocks/$id/summary", body))
    }

    suspend fun fetchTranslation(id: Int): StockTranslationPayload =
        client.send(Endpoint.get("/api/stocks/$id/translation"), StockTranslationPayload.serializer())

    suspend fun saveTranslation(id: Int, segments: String) {
        val body = buildJsonObject { put("segments", segments) }.toString()
        client.sendVoid(Endpoint.put("/api/stocks/$id/translation", body))
    }

    /// URL（正規化後）で既存ストックを検索する（共有シート等で追加前に既存か確認する用途）
    suspend fun lookup(url: String): Stock? {
        val response = client.send(
            Endpoint.get("/api/stocks/lookup", listOf("url" to url)),
            StockLookupResponse.serializer(),
        )
        return response.stock
    }

    suspend fun fetchCategories(): List<StockCategory> =
        client.send(Endpoint.get("/api/stock-categories"), ListSerializer(StockCategory.serializer()))

    suspend fun reorderCategories(ids: List<Int>) {
        val body = buildJsonObject { putJsonArray("ids") { ids.forEach { add(it) } } }.toString()
        client.sendVoid(Endpoint.patch("/api/stock-categories/reorder", body))
    }
}
