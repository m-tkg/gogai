package com.mtkg.gogai.ai

import com.mtkg.gogai.cache.InMemoryKeyValueStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class TranslationMixTest {
    private fun translatedIndices(count: Int, ratio: Int, offset: Int = 0): List<Int> =
        (0 until count).filter { TranslationMix.isTranslated(it, ratio, offset) }

    @Test
    fun `100パーセントなら全文が訳文`() {
        assertEquals(listOf(0, 1, 2, 3, 4), translatedIndices(5, 100))
    }

    @Test
    fun `0パーセントなら訳文なし`() {
        assertEquals(emptyList<Int>(), translatedIndices(5, 0))
    }

    @Test
    fun `割合どおりの文数が均等に散らばる`() {
        assertEquals(4, translatedIndices(10, 40).size)
        assertEquals(listOf(1, 3, 5, 7, 9), translatedIndices(10, 50))
        assertEquals(30, translatedIndices(100, 30).size)
    }

    @Test
    fun `オフセットを変えると別の文が選ばれる`() {
        val a = translatedIndices(10, 50, offset = 0)
        val b = translatedIndices(10, 50, offset = 1)
        assertNotEquals(a, b)
        assertEquals(a.size, b.size)
    }

    @Test
    fun `範囲外の割合はクランプされる`() {
        assertEquals(0, TranslationMix.clamp(-10))
        assertEquals(100, TranslationMix.clamp(150))
        assertEquals(listOf(0, 1, 2), translatedIndices(3, 150))
    }

    @Test
    fun `savedRatio は未設定なら既定値`() {
        assertEquals(TranslationMix.DEFAULT_RATIO, TranslationMix.savedRatio(InMemoryKeyValueStore()))
    }

    @Test
    fun `savedRatio の保存と読み出し`() {
        val store = InMemoryKeyValueStore()
        TranslationMix.saveRatio(store, 70)
        assertEquals(70, TranslationMix.savedRatio(store))
        TranslationMix.saveRatio(store, 999)
        assertEquals("範囲外はクランプして保存する", 100, TranslationMix.savedRatio(store))
    }

    @Test
    fun `savedRatio は不正な文字列なら既定値`() {
        val store = InMemoryKeyValueStore()
        store.putString("translationMixRatio", "abc")
        assertEquals(TranslationMix.DEFAULT_RATIO, TranslationMix.savedRatio(store))
    }
}
