package com.mtkg.gogai.ai

import com.mtkg.gogai.cache.DefaultsKeys
import com.mtkg.gogai.cache.KeyValueStore

/**
 * 文単位ミックス翻訳の「訳文で表示する文の割合」を扱う(iOS の `TranslationMix.swift` の移植)。
 * 文の通し番号に対して割合どおりに均等に訳文を散らし(Bresenham 的な整数演算)、
 * offset をずらすことで「混ぜ直し」を表現する。
 */
object TranslationMix {
    const val MIN_RATIO = 0
    const val MAX_RATIO = 100
    const val STEP = 10
    /** 初期値。参考: 参照実装(Mazelingo)の既定値 40% */
    const val DEFAULT_RATIO = 40

    /** 通し番号 index の文を訳文で表示するかどうか(ratio は 0〜100 のパーセント) */
    fun isTranslated(index: Int, ratio: Int, offset: Int = 0): Boolean {
        val r = clamp(ratio)
        val j = index + offset
        return ((j + 1) * r) / 100 > (j * r) / 100
    }

    fun clamp(ratio: Int): Int = ratio.coerceIn(MIN_RATIO, MAX_RATIO)

    /** 保存した割合(未設定・不正値なら DEFAULT_RATIO) */
    fun savedRatio(store: KeyValueStore): Int =
        store.getString(DefaultsKeys.TRANSLATION_MIX_RATIO)?.toIntOrNull()?.let { clamp(it) } ?: DEFAULT_RATIO

    fun saveRatio(store: KeyValueStore, ratio: Int) {
        store.putString(DefaultsKeys.TRANSLATION_MIX_RATIO, clamp(ratio).toString())
    }
}
