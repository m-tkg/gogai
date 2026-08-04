package com.mtkg.gogai.cache

import android.content.SharedPreferences

/// UserDefaults 相当の同期 key-value 永続化（テストでは in-memory fake に差し替える）
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun getBoolean(key: String, default: Boolean): Boolean
    fun putBoolean(key: String, value: Boolean)
    fun remove(key: String)
}

class SharedPreferencesStore(private val prefs: SharedPreferences) : KeyValueStore {
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String) = prefs.edit().putString(key, value).apply()
    override fun getBoolean(key: String, default: Boolean): Boolean = prefs.getBoolean(key, default)
    override fun putBoolean(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    override fun remove(key: String) = prefs.edit().remove(key).apply()
}

class InMemoryKeyValueStore : KeyValueStore {
    private val values = mutableMapOf<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getBoolean(key: String, default: Boolean): Boolean = values[key] as? Boolean ?: default
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}
