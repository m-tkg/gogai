package com.mtkg.gogai.store

import com.mtkg.gogai.cache.SecretStore
import com.mtkg.gogai.model.Settings
import com.mtkg.gogai.model.UpdateCheck
import com.mtkg.gogai.network.ApiClient
import com.mtkg.gogai.network.ApiException
import com.mtkg.gogai.repository.SettingsRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/// 設定・サーバー管理を保持する Store（iOS SettingsStore の移植）。
/// SettingsRepository のコンストラクタが (client, secretStore) を要求するため、
/// iOS 版が client のみを保持するのに対し Android 版は secretStore も保持する。
class SettingsStore {
    private val _settings = MutableStateFlow<Settings?>(null)
    val settings: StateFlow<Settings?> = _settings.asStateFlow()

    private val _updateCheck = MutableStateFlow<UpdateCheck?>(null)
    val updateCheck: StateFlow<UpdateCheck?> = _updateCheck.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()

    private var client: ApiClient? = null
    private var secretStore: SecretStore? = null

    fun configure(client: ApiClient, secretStore: SecretStore) {
        this.client = client
        this.secretStore = secretStore
    }

    private fun repository(): SettingsRepository? {
        val client = this.client ?: return null
        val secretStore = this.secretStore ?: return null
        return SettingsRepository(client, secretStore)
    }

    suspend fun fetchSettings() {
        val repository = repository() ?: return
        try {
            _settings.value = repository.fetch()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.value = e
        }
    }

    suspend fun updateRetentionDays(days: Int) {
        val repository = repository() ?: return
        _settings.value = repository.update(days)
    }

    suspend fun checkUpdate() {
        val repository = repository() ?: return
        _isLoading.value = true
        try {
            _updateCheck.value = repository.checkUpdate()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _error.value = e
        } finally {
            _isLoading.value = false
        }
    }

    suspend fun restart(): String {
        val repository = repository() ?: throw ApiException.InvalidUrl()
        return repository.restart()
    }
}
