package com.mtkg.gogai.store

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

private data class Item(val id: Int)
private class ReorderTestException : Exception()

class ReorderHelperTest {
    @Test
    fun `指定した範囲を並び替えてid配列をpersistに渡す`() = runTest {
        val items = listOf(Item(1), Item(2), Item(3))
        var persistedIds: List<Int>? = null

        val result = reorderAndPersist(items, from = 2, to = 0, idOf = { it.id }) { ids ->
            persistedIds = ids
        }

        assertEquals(listOf(3, 1, 2), result.map { it.id })
        assertEquals(listOf(3, 1, 2), persistedIds)
    }

    @Test
    fun `末尾への移動もpersistに渡す`() = runTest {
        val items = listOf(Item(1), Item(2), Item(3))
        var persistedIds: List<Int>? = null

        val result = reorderAndPersist(items, from = 0, to = 3, idOf = { it.id }) { ids ->
            persistedIds = ids
        }

        assertEquals(listOf(2, 3, 1), result.map { it.id })
        assertEquals(listOf(2, 3, 1), persistedIds)
    }

    @Test
    fun `persistが失敗したら配列を返さずthrowする`() = runTest {
        val items = listOf(Item(1), Item(2))

        try {
            reorderAndPersist(items, from = 0, to = 2, idOf = { it.id }) {
                throw ReorderTestException()
            }
            fail("例外が throw されるはず")
        } catch (e: ReorderTestException) {
            // 期待通り
        }
    }
}
