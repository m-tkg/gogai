package com.mtkg.gogai.store

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/// StockStore の要約キュー（生成中・待機中・エラー・一時停止）の状態と実行ロジックを保持する
/// （iOS SummaryQueue の移植）。
/// オンデバイス AI は同時に1リクエストしか処理できないため、常に直列実行する。
/// 永続化（KeyValueStore 保存）は行わない（呼び出し側の StockStore が担う）。
///
/// iOS 版は Swift の `actor` 化を避け、@MainActor クラスとして完全に同期的に動かしている
/// （呼び出し直後に同期的に状態を検証するテストが複数あるため）。Kotlin 版も同様に、
/// [scope] が Dispatchers.Main.immediate 前提であることを利用し、状態遷移（pending/
/// currentlySummarizing/errors/isPausedByUser の変更）はすべて同期的に行う。ロックは不要。
class SummaryQueue(private val scope: CoroutineScope) {
    /// 実行待ちのストック ID（先頭が次に実行される）
    var pending: List<Int> = emptyList()
        private set(value) {
            field = value
            onChange?.invoke()
        }

    /// 現在生成中のストック ID
    var currentlySummarizing: Int? = null
        private set(value) {
            field = value
            onChange?.invoke()
        }

    /// ストックIDごとの直近の要約失敗メッセージ
    var errors: Map<Int, String> = emptyMap()
        private set(value) {
            field = value
            onChange?.invoke()
        }

    /// ユーザーが一時停止ボタンで止めたかどうか（翻訳優先による一時停止とは別軸）
    var isPausedByUser: Boolean = false
        private set(value) {
            field = value
            onChange?.invoke()
        }

    /// 状態が変わるたびに同期的に呼ばれる。StockStore が自分の StateFlow へミラーする。
    var onChange: (() -> Unit)? = null

    /// 実際に1件要約する処理の委譲先。StockStore が自身を設定する。
    var performSummary: (suspend (stockId: Int) -> Unit)? = null

    private var job: Job? = null

    /// 翻訳優先のため自動的に一時停止しているか
    private var isPausedForTranslation = false

    /// 実行中にキャンセルされ、完了後もキューへ戻さない対象（一時停止との違いはここ）
    private val cancelledIds = mutableSetOf<Int>()

    /// 実際のキューを進めてよいか（翻訳優先 or ユーザー操作のどちらかで停止していれば false）
    private val isPaused: Boolean
        get() = isPausedForTranslation || isPausedByUser

    /// 要約をキューに追加する（fire-and-forget）。既に生成中/待機中のストックは無視する。
    fun enqueue(stockId: Int) {
        if (currentlySummarizing == stockId || pending.contains(stockId)) return
        errors = errors - stockId
        pending = pending + stockId
        drive()
    }

    /// 翻訳を優先させるため、実行中の要約があれば中断してキュー処理を一時停止する。
    /// 中断された要約は再開時に最初からやり直す（オンデバイスモデルに部分再開の手段が無いため）。
    ///
    /// job はここで同期的に null クリアする（キャンセルされたタスク自身の後片付けを待たない）。
    /// そうしないと、キャンセル後すぐに resumeAfterTranslation で新しいタスクを開始した場合、
    /// 遅れて実行される旧タスクの後片付けが新タスクの参照を誤ってクリアしてしまうレースが
    /// 起こり得る（drive() の再入防止ガードが壊れる）。
    fun pauseForTranslation() {
        isPausedForTranslation = true
        job?.cancel()
        job = null
    }

    /// 翻訳完了後、要約キューを再開する。ユーザーが一時停止中の場合は再開しない。
    fun resumeAfterTranslation() {
        isPausedForTranslation = false
        drive()
    }

    /// ユーザー操作による一時停止。実行中の要約があれば中断し、キュー先頭へ戻す（やり直せるように）。
    /// 翻訳優先の一時停止とは独立して管理するため、翻訳が終わっても自動再開されない。
    fun pauseByUser() {
        isPausedByUser = true
        job?.cancel()
        job = null
    }

    /// ユーザー操作による一時停止を解除する。翻訳優先の一時停止が別途かかっている場合は
    /// （isPaused が true のままなので）drive() 側のガードで開始されない。
    fun resumeByUser() {
        isPausedByUser = false
        drive()
    }

    /// キュー内の特定のストックをキャンセルする。待機中ならキューから外すだけ、
    /// 生成中なら中断し、一時停止と違い完了後もキューへ戻さない（cancelledIds で判別）。
    fun cancel(stockId: Int) {
        pending = pending.filterNot { it == stockId }
        errors = errors - stockId
        if (currentlySummarizing != stockId) return
        cancelledIds.add(stockId)
        job?.cancel()
        job = null
    }

    /// エラーアラートを閉じた後の表示クリア用。
    fun clearError(stockId: Int) {
        errors = errors - stockId
    }

    /// 永続化されたキューから復元する（現在キューが空のときのみ）。
    /// ids は呼び出し側（StockStore）が既に「削除済み/他端末で完了済み」を除外した状態で渡すこと。
    fun restorePending(ids: List<Int>) {
        if (pending.isNotEmpty() || currentlySummarizing != null || ids.isEmpty()) return
        pending = ids
        drive()
    }

    /// 永続化されたエラーから復元する（全置換）。
    /// restored は呼び出し側が既に「削除済み/要約済み」を除外した状態で渡すこと。
    fun restoreErrors(restored: Map<Int, String>) {
        errors = restored
    }

    private fun drive() {
        if (job != null || isPaused) return
        job = scope.launch {
            run()
            // pauseForTranslation/pauseByUser/cancel は自分で job を同期的に null クリアするため、
            // キャンセルされて戻ってきた場合はここで触らない（新しいタスクの参照を壊さないため）。
            if (isActive) {
                job = null
            }
        }
    }

    private suspend fun run() {
        while (!isPaused && pending.isNotEmpty()) {
            val stockId = pending.first()
            pending = pending.drop(1)
            currentlySummarizing = stockId
            try {
                performSummary?.invoke(stockId)
            } catch (e: CancellationException) {
                if (cancelledIds.remove(stockId)) {
                    // ユーザーが明示的にキャンセルした分は再投入しない
                    currentlySummarizing = null
                    return
                }
                // 翻訳優先 or ユーザーの一時停止により中断された。やり直せるようキュー先頭へ戻して終了する。
                pending = listOf(stockId) + pending
                currentlySummarizing = null
                return
            } catch (e: Exception) {
                errors = errors + (stockId to (e.message ?: e.toString()))
            }
            currentlySummarizing = null
        }
    }
}
