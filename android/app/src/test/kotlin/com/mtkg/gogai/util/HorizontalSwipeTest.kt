package com.mtkg.gogai.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HorizontalSwipeTest {
    @Test
    fun `dx が 80 ちょうどは不成立`() {
        assertNull(matchHorizontalSwipe(dx = 80f, dy = 0f))
        assertNull(matchHorizontalSwipe(dx = -80f, dy = 0f))
    }

    @Test
    fun `dx が 81 は成立する`() {
        assertEquals(HorizontalSwipeDirection.Right, matchHorizontalSwipe(dx = 81f, dy = 0f))
        assertEquals(HorizontalSwipeDirection.Left, matchHorizontalSwipe(dx = -81f, dy = 0f))
    }

    @Test
    fun `dy が dx の半分ちょうどは不成立(境界)`() {
        // |dx| = 100, |dy| = 50 = |dx| * 0.5 -> dy < dx * 0.5 を満たさない
        assertNull(matchHorizontalSwipe(dx = 100f, dy = 50f))
        assertNull(matchHorizontalSwipe(dx = -100f, dy = -50f))
    }

    @Test
    fun `dy が dx の半分未満なら成立する`() {
        assertEquals(HorizontalSwipeDirection.Right, matchHorizontalSwipe(dx = 100f, dy = 49f))
        assertEquals(HorizontalSwipeDirection.Left, matchHorizontalSwipe(dx = -100f, dy = -49f))
    }

    @Test
    fun `縦方向優位のドラッグは不成立`() {
        assertNull(matchHorizontalSwipe(dx = 90f, dy = 90f))
    }
}
