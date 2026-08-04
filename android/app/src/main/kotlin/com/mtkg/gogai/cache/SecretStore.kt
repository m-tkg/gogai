package com.mtkg.gogai.cache

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Keychain 相当のシークレット保存（iOS KeychainStore の移植）
interface SecretStore {
    fun get(key: String): String?
    fun set(key: String, value: String)
    fun remove(key: String)

    companion object {
        const val ADMIN_SECRET = "adminSecret"
        const val OPENAI_API_KEY = "openAIAPIKey"
        const val GEMINI_API_KEY = "geminiAPIKey"
        const val CLAUDE_API_KEY = "claudeAPIKey"
    }
}

class InMemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, String>()
    override fun get(key: String): String? = values[key]
    override fun set(key: String, value: String) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

/// Android Keystore の AES/GCM 鍵で値を暗号化して SharedPreferences に保存する。
/// （EncryptedSharedPreferences は非推奨のため自前の最小実装）
class KeystoreSecretStore(private val prefs: SharedPreferences) : SecretStore {
    companion object {
        private const val KEY_ALIAS = "com.mtkg.gogai.secrets"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    override fun get(key: String): String? {
        val stored = prefs.getString(key, null) ?: return null
        return runCatching {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val ivLength = bytes[0].toInt()
            val iv = bytes.copyOfRange(1, 1 + ivLength)
            val encrypted = bytes.copyOfRange(1 + ivLength, bytes.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        }.getOrNull()
    }

    override fun set(key: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        val combined = byteArrayOf(iv.size.toByte()) + iv + encrypted
        prefs.edit().putString(key, Base64.encodeToString(combined, Base64.NO_WRAP)).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }
}
