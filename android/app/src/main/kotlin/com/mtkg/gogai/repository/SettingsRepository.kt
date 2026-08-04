package com.mtkg.gogai.repository

import com.mtkg.gogai.cache.SecretStore
import com.mtkg.gogai.model.Settings
import com.mtkg.gogai.model.UpdateCheck
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.Endpoint
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
private data class RestartResult(val output: String)

/// 設定・管理 API（iOS SettingsRepository の移植）
class SettingsRepository(private val client: ApiClient, private val secretStore: SecretStore) {

    suspend fun fetch(): Settings = client.send(Endpoint.get("/api/settings"), Settings.serializer())

    suspend fun update(retentionDays: Int): Settings {
        val body = buildJsonObject { put("retention_days", retentionDays) }.toString()
        return client.send(Endpoint.put("/api/settings", body), Settings.serializer())
    }

    suspend fun checkUpdate(): UpdateCheck =
        client.send(Endpoint.get("/api/admin/update-check", headers = adminHeaders()), UpdateCheck.serializer())

    suspend fun restart(): String {
        val result = client.send(Endpoint.post("/api/admin/restart", headers = adminHeaders()), RestartResult.serializer())
        return result.output
    }

    /// サーバー側で ADMIN_SECRET が設定されている場合のみ検証される認証ヘッダー。
    /// 未設定（SecretStore に何も保存していない）の場合は空のまま送る（opt-in のため無認証でも通る）。
    private fun adminHeaders(): Map<String, String> {
        val secret = secretStore.get(SecretStore.ADMIN_SECRET)
        return if (!secret.isNullOrEmpty()) mapOf("X-Admin-Secret" to secret) else emptyMap()
    }
}
