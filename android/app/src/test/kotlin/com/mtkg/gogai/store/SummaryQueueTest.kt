package com.mtkg.gogai.store

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SummaryQueueTest {
    private val testDispatcher = StandardTestDispatcher()
    private lateinit var scope: CoroutineScope
    private lateinit var queue: SummaryQueue

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        scope = CoroutineScope(testDispatcher)
        queue = SummaryQueue(scope)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `enqueue は要約処理を開始する`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        queue.performSummary = { id -> started.add(id) }

        queue.enqueue(1)
        advanceUntilIdle()

        assertEquals(listOf(1), started)
        assertNull(queue.currentlySummarizing)
        assertTrue(queue.pending.isEmpty())
    }

    @Test
    fun `2件目は1件目が完了するまで開始しない`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { id ->
            started.add(id)
            if (id == 1) gate.await()
        }

        queue.enqueue(1)
        queue.enqueue(2)
        runCurrent()

        assertEquals(listOf(1), started)
        assertEquals(1, queue.currentlySummarizing)
        assertEquals(listOf(2), queue.pending)

        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals(listOf(1, 2), started)
        assertNull(queue.currentlySummarizing)
        assertTrue(queue.pending.isEmpty())
    }

    @Test
    fun `既にキュー済み_実行中のIDは重複追加しない`() = runTest(testDispatcher) {
        val gate = CompletableDeferred<Unit>()
        var callCount = 0
        queue.performSummary = { callCount++; gate.await() }

        queue.enqueue(1)
        runCurrent()
        queue.enqueue(1) // 実行中なので無視される

        assertEquals(listOf<Int>(), queue.pending)

        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, callCount)
    }

    @Test
    fun `失敗しても次のキューは処理を続ける`() = runTest(testDispatcher) {
        val processed = mutableListOf<Int>()
        queue.performSummary = { id ->
            processed.add(id)
            if (id == 1) throw RuntimeException("boom")
        }

        queue.enqueue(1)
        queue.enqueue(2)
        advanceUntilIdle()

        assertEquals(listOf(1, 2), processed)
        assertEquals("boom", queue.errors[1])
        assertNull(queue.errors[2])
    }

    @Test
    fun `enqueue はエラーをクリアしてから追加する`() = runTest(testDispatcher) {
        queue.performSummary = { throw RuntimeException("boom") }
        queue.enqueue(1)
        advanceUntilIdle()
        assertEquals("boom", queue.errors[1])

        queue.performSummary = { }
        queue.enqueue(1)
        runCurrent()
        assertNull(queue.errors[1])
    }

    @Test
    fun `pauseForTranslation は実行中の要約を中断しキュー先頭へ戻す`() = runTest(testDispatcher) {
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { gate.await() }

        queue.enqueue(1)
        runCurrent()
        assertEquals(1, queue.currentlySummarizing)

        queue.pauseForTranslation()
        advanceUntilIdle()

        assertNull(queue.currentlySummarizing)
        assertEquals(listOf(1), queue.pending)
    }

    @Test
    fun `resumeSummaryQueueAfterTranslation は中断した要約を再開する`() = runTest(testDispatcher) {
        var callCount = 0
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { callCount++; if (callCount == 1) gate.await() }

        queue.enqueue(1)
        runCurrent()
        queue.pauseForTranslation()
        advanceUntilIdle()

        queue.resumeAfterTranslation()
        advanceUntilIdle()

        assertEquals(2, callCount)
        assertNull(queue.currentlySummarizing)
        assertTrue(queue.pending.isEmpty())
    }

    @Test
    fun `pauseByUser は実行中の要約を中断しキュー先頭へ戻す`() = runTest(testDispatcher) {
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { gate.await() }

        queue.enqueue(1)
        runCurrent()

        queue.pauseByUser()
        advanceUntilIdle()

        assertTrue(queue.isPausedByUser)
        assertEquals(listOf(1), queue.pending)
    }

    @Test
    fun `一時停止中は新規キューを開始しない`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        queue.performSummary = { id -> started.add(id) }

        queue.pauseByUser()
        queue.enqueue(1)
        advanceUntilIdle()

        assertTrue(started.isEmpty())
        assertEquals(listOf(1), queue.pending)
    }

    @Test
    fun `resumeByUser は一時停止解除で処理を再開する`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        queue.performSummary = { id -> started.add(id) }

        queue.pauseByUser()
        queue.enqueue(1)
        advanceUntilIdle()
        assertTrue(started.isEmpty())

        queue.resumeByUser()
        advanceUntilIdle()

        assertEquals(listOf(1), started)
        assertFalse(queue.isPausedByUser)
    }

    @Test
    fun `翻訳優先の一時停止中はresumeByUserでは開始しない`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        queue.performSummary = { id -> started.add(id) }

        queue.pauseForTranslation()
        queue.pauseByUser()
        queue.enqueue(1)
        advanceUntilIdle()

        queue.resumeByUser()
        advanceUntilIdle()

        assertTrue(started.isEmpty())
    }

    @Test
    fun `cancel はキュー内の未実行ストックを削除する`() = runTest(testDispatcher) {
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { id -> if (id == 1) gate.await() }

        queue.enqueue(1)
        queue.enqueue(2)
        runCurrent()

        queue.cancel(2)

        assertEquals(emptyList<Int>(), queue.pending)

        gate.complete(Unit)
        advanceUntilIdle()
    }

    @Test
    fun `cancel は実行中のストックはキャンセル後に再投入されない`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { id -> started.add(id); gate.await() }

        queue.enqueue(1)
        runCurrent()
        assertEquals(1, queue.currentlySummarizing)

        queue.cancel(1)
        advanceUntilIdle()

        assertNull(queue.currentlySummarizing)
        assertTrue(queue.pending.isEmpty())
    }

    @Test
    fun `clearError は指定したストックのエラーだけ消す`() = runTest(testDispatcher) {
        queue.performSummary = { id -> throw RuntimeException("err-$id") }
        queue.enqueue(1)
        queue.enqueue(2)
        advanceUntilIdle()

        assertEquals("err-1", queue.errors[1])
        assertEquals("err-2", queue.errors[2])

        queue.clearError(1)

        assertNull(queue.errors[1])
        assertEquals("err-2", queue.errors[2])
    }

    @Test
    fun `restorePending はキューが空のときのみ復元する`() = runTest(testDispatcher) {
        val started = mutableListOf<Int>()
        val gate = CompletableDeferred<Unit>()
        queue.performSummary = { id -> started.add(id); if (id == 9) gate.await() }

        queue.restorePending(listOf(1, 2))
        advanceUntilIdle()
        assertEquals(listOf(1, 2), started)

        // 実行中のときは復元しない
        started.clear()
        queue.enqueue(9)
        runCurrent()
        queue.restorePending(listOf(3, 4))
        assertTrue(queue.pending.isEmpty())

        gate.complete(Unit)
        advanceUntilIdle()
    }

    @Test
    fun `restorePending は空リストなら何もしない`() = runTest(testDispatcher) {
        queue.performSummary = { }
        queue.restorePending(emptyList())
        assertTrue(queue.pending.isEmpty())
    }

    @Test
    fun `restoreErrors は全置換する`() {
        queue.restoreErrors(mapOf(1 to "a", 2 to "b"))
        assertEquals(mapOf(1 to "a", 2 to "b"), queue.errors)

        queue.restoreErrors(mapOf(3 to "c"))
        assertEquals(mapOf(3 to "c"), queue.errors)
    }

    @Test
    fun `onChange は状態変化のたびに呼ばれる`() = runTest(testDispatcher) {
        var changeCount = 0
        queue.onChange = { changeCount++ }
        queue.performSummary = { }

        queue.enqueue(1)
        advanceUntilIdle()

        assertTrue(changeCount > 0)
    }
}
