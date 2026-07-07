import Foundation

/// SummaryQueue が実際の要約生成処理を委譲する先。StockStore が実装する。
/// クロージャではなく delegate にしているのは、StockStore.init()(非 actor-isolated
/// コンテキスト、テストの setUp() から同期生成されるため)内で self を @MainActor
/// クロージャへキャプチャすると Swift 6 の region isolation チェックに
/// 「task-isolated self を @MainActor クロージャへ送信するリスク」として弾かれるため。
/// delegate への単純な参照代入(弱参照)はこの問題を起こさない。
protocol SummaryQueueDelegate: AnyObject {
    @MainActor func summaryQueue(_ queue: SummaryQueue, performSummaryFor stockId: Int, session: URLSession) async throws
}

/// StockStore の要約キュー(生成中・待機中・エラー・一時停止)の状態と実行ロジックを保持する。
/// オンデバイス AI は同時に1リクエストしか処理できないため(LanguageModelSession.Error.concurrentRequests)、
/// 常に直列実行する。永続化(UserDefaults 保存)は行わない(呼び出し側の StockStore が担う)。
///
/// 設計判断: 計画では Swift `actor` を推奨していたが、StockStoreTests には
/// `store.requestSummary(...)` 呼び出し直後(await を挟まない同期テスト関数内)に
/// `store.pendingSummaryStockIds` 等を同期的に検証するテストが複数ある
/// (例: 一時停止中に requestSummary してもキューが進まないことの確認)。
/// SummaryQueue を真の `actor` にすると、呼び出し元(@MainActor の StockStore)からの
/// 状態アクセスに await が必要になり、これらの同期アサーションが成立しなくなる
/// (テストの書き換えが必要になる)。そのため既存の Store 規約(クラスレベル @MainActor を
/// 付けず、メソッド単位で付ける)をそのまま踏襲し、StockStore と同じ実行コンテキストで
/// 完全に同期的に動作させる(既存テストを変更しない)。
final class SummaryQueue {
    /// 実行待ちのストック ID(先頭が次に実行される)
    private(set) var pending: [Int] = [] {
        didSet { onChange?() }
    }
    /// 現在生成中のストック ID
    private(set) var currentlySummarizing: Int? {
        didSet { onChange?() }
    }
    /// ストックIDごとの直近の要約失敗メッセージ
    private(set) var errors: [Int: String] = [:] {
        didSet { onChange?() }
    }
    /// ユーザーが一時停止ボタンで止めたかどうか(翻訳優先による一時停止とは別軸)
    private(set) var isPausedByUser = false {
        didSet { onChange?() }
    }

    /// 状態が変わるたびに同期的に呼ばれる。StockStore が自分の @Published プロパティへミラーする。
    var onChange: (() -> Void)?

    private var task: Task<Void, Never>?
    /// 翻訳優先のため自動的に一時停止しているか(#126 参照)
    private var isPausedForTranslation = false
    /// 実行中にキャンセルされ、完了後もキューへ戻さない対象(一時停止との違いはここ)
    private var cancelledIds: Set<Int> = []
    /// drive() が最後に呼ばれたときのセッション。run() の while ループ全体で使い回す。
    private var session: URLSession = .shared

    /// 実際に1件要約する処理の委譲先。StockStore が自身を設定する。
    weak var delegate: SummaryQueueDelegate?

    /// 実際のキューを進めてよいか(翻訳優先 or ユーザー操作のどちらかで停止していれば false)
    private var isPaused: Bool {
        isPausedForTranslation || isPausedByUser
    }

    /// 要約をキューに追加する(fire-and-forget)。既に生成中/待機中のストックは無視する。
    @MainActor
    func enqueue(stockId: Int, session: URLSession = .shared) {
        guard currentlySummarizing != stockId, !pending.contains(stockId) else { return }
        errors[stockId] = nil
        pending.append(stockId)
        drive(session: session)
    }

    /// 翻訳を優先させるため、実行中の要約があれば中断してキュー処理を一時停止する。
    /// 中断された要約は再開時に最初からやり直す(オンデバイスモデルに部分再開の手段が無いため)。
    ///
    /// task はここで同期的に nil クリアする(キャンセルされたタスク自身の後片付けを待たない)。
    /// そうしないと、キャンセル後すぐに resumeAfterTranslation で新しいタスクを開始した場合、
    /// 遅れて実行される旧タスクの後片付けが新タスクの参照を誤ってクリアしてしまうレースが
    /// 起こり得る(drive() の再入防止ガードが壊れる)。
    @MainActor
    func pauseForTranslation() {
        isPausedForTranslation = true
        task?.cancel()
        task = nil
    }

    /// 翻訳完了後、要約キューを再開する。ユーザーが一時停止中の場合は再開しない。
    @MainActor
    func resumeAfterTranslation(session: URLSession = .shared) {
        isPausedForTranslation = false
        drive(session: session)
    }

    /// ユーザー操作による一時停止。実行中の要約があれば中断し、キュー先頭へ戻す(やり直せるように)。
    /// 翻訳優先の一時停止とは独立して管理するため、翻訳が終わっても自動再開されない。
    @MainActor
    func pauseByUser() {
        isPausedByUser = true
        task?.cancel()
        task = nil
    }

    /// ユーザー操作による一時停止を解除する。翻訳優先の一時停止が別途かかっている場合は
    /// (isPaused が true のままなので)drive() 側のガードで開始されない。
    @MainActor
    func resumeByUser(session: URLSession = .shared) {
        isPausedByUser = false
        drive(session: session)
    }

    /// キュー内の特定のストックをキャンセルする。待機中ならキューから外すだけ、
    /// 生成中なら中断し、一時停止と違い完了後もキューへ戻さない(cancelledIds で判別)。
    @MainActor
    func cancel(stockId: Int) {
        pending.removeAll { $0 == stockId }
        errors[stockId] = nil
        guard currentlySummarizing == stockId else { return }
        cancelledIds.insert(stockId)
        task?.cancel()
        task = nil
    }

    /// エラーアラートを閉じた後の表示クリア用。
    @MainActor
    func clearError(for stockId: Int) {
        errors[stockId] = nil
    }

    /// 永続化されたキューから復元する(現在キューが空のときのみ)。
    /// ids は呼び出し側(StockStore)が既に「削除済み/他端末で完了済み」を除外した状態で渡すこと。
    @MainActor
    func restorePending(_ ids: [Int], session: URLSession = .shared) {
        guard pending.isEmpty, currentlySummarizing == nil, !ids.isEmpty else { return }
        pending = ids
        drive(session: session)
    }

    /// 永続化されたエラーから復元する(全置換)。
    /// restored は呼び出し側が既に「削除済み/要約済み」を除外した状態で渡すこと。
    @MainActor
    func restoreErrors(_ restored: [Int: String]) {
        errors = restored
    }

    @MainActor
    private func drive(session: URLSession) {
        guard task == nil, !isPaused else { return }
        self.session = session
        task = Task { [weak self] in
            await self?.run()
            // pauseForTranslation/pauseByUser/cancel は自分で task を同期的にクリアするため、
            // キャンセルされて戻ってきた場合はここで触らない(新しいタスクの参照を壊さないため)。
            if !Task.isCancelled {
                self?.task = nil
            }
        }
    }

    @MainActor
    private func run() async {
        while !isPaused, !pending.isEmpty {
            let stockId = pending.removeFirst()
            currentlySummarizing = stockId
            do {
                try await delegate?.summaryQueue(self, performSummaryFor: stockId, session: session)
            } catch is CancellationError {
                if cancelledIds.remove(stockId) != nil {
                    // ユーザーが明示的にキャンセルした分は再投入しない
                    currentlySummarizing = nil
                    return
                }
                // 翻訳優先 or ユーザーの一時停止により中断された。やり直せるようキュー先頭へ戻して終了する。
                pending.insert(stockId, at: 0)
                currentlySummarizing = nil
                return
            } catch {
                errors[stockId] = error.localizedDescription
            }
            currentlySummarizing = nil
        }
    }
}
