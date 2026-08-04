package com.mtkg.gogai.ai

import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.KeyValueStore
import com.mtkg.gogai.cache.SecretStore

/**
 * 要約・翻訳に使う AI プロバイダ（iOS の AIProvider, AI/LocalArticleAI.swift の移植）。
 * rawValue は iOS と同一文字列を使う。iOS 版と異なり Android はオンデバイスモデルを持たないため
 * `onDevice` ケースは存在しない（Gogai Android は AI をリモート API のみで提供する方針）。
 */
enum class AiProvider(val rawValue: String) {
    Automatic("automatic"),
    OpenAI("openAI"),
    Gemini("gemini"),
    Claude("claude"),
    ;

    val label: String
        get() = when (this) {
            Automatic -> "自動"
            OpenAI -> "OpenAI"
            Gemini -> "Gemini"
            Claude -> "Claude"
        }

    private val secretKey: String?
        get() = when (this) {
            Automatic -> null
            OpenAI -> SecretStore.OPENAI_API_KEY
            Gemini -> SecretStore.GEMINI_API_KEY
            Claude -> SecretStore.CLAUDE_API_KEY
        }

    /** 保存済みの API キー（未設定・空文字なら null） */
    fun apiKey(secretStore: SecretStore): String? {
        val key = secretKey ?: return null
        val value = secretStore.get(key)?.trim().orEmpty()
        return value.ifEmpty { null }
    }

    companion object {
        fun fromRawValue(raw: String?): AiProvider = entries.firstOrNull { it.rawValue == raw } ?: Automatic
    }
}

/** DefaultsKeys.AI_PROVIDER に永続化された現在のプロバイダ設定を取得する */
fun currentAiProvider(store: KeyValueStore): AiProvider =
    AiProvider.fromRawValue(store.getString(DefaultsKeys.AI_PROVIDER))

/** DefaultsKeys.AI_PROVIDER に現在のプロバイダ設定を保存する */
fun setCurrentAiProvider(store: KeyValueStore, provider: AiProvider) {
    store.putString(DefaultsKeys.AI_PROVIDER, provider.rawValue)
}

/**
 * 実際に使用可能なプロバイダを解決する（iOS LocalAI.resolvedProvider の移植。オンデバイス分岐は除く）。
 * this が [AiProvider.Automatic] の場合は OpenAI → Gemini → Claude の順にキー設定済みのプロバイダを探す
 * （オンデバイスの選択肢はない）。それ以外の場合は自分自身のキーが設定されていればそれを返す。
 * どちらも該当なしなら null。
 */
fun AiProvider.resolve(secretStore: SecretStore): AiProvider? = when (this) {
    AiProvider.Automatic ->
        listOf(AiProvider.OpenAI, AiProvider.Gemini, AiProvider.Claude)
            .firstOrNull { it.apiKey(secretStore) != null }
    else -> if (this.apiKey(secretStore) != null) this else null
}
