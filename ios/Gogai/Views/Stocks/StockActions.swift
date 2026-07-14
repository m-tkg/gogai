import SwiftUI

/// StockRowView/StockDetailView が共通して必要とする、StockStore(要約キュー)から導出される
/// 計算値と削除実行ロジックをまとめる。確認ダイアログの表示トリガーなど View 固有の
/// 遷移・タイミングを持つ @State はここに含めず、各 View に残す。
struct StockActions {
    let stockStore: StockStore
    /// stockStore.stocks にまだ反映されていない場合(作成直後など)のフォールバック
    let fallbackStock: Stock
    @Binding var deleteError: Error?

    /// View のライフサイクルに依存しないストアのキュー状態を見る(画面遷移してもキューは継続する)。
    var currentStock: Stock {
        stockStore.stocks.first(where: { $0.id == fallbackStock.id }) ?? fallbackStock
    }

    var isGeneratingSummary: Bool {
        stockStore.currentlySummarizingStockId == currentStock.id || isQueued
    }

    var isQueued: Bool {
        stockStore.pendingSummaryStockIds.contains(currentStock.id)
    }

    var summaryError: String? {
        stockStore.summaryErrors[currentStock.id]
    }

    var summaryProgressLogs: [String] {
        stockStore.summaryProgressLogs[currentStock.id] ?? []
    }

    /// 翻訳を実行できる(または結果を再確認できる)条件:
    /// この端末で AI が使えるか、既に翻訳済みで結果が保存されているか
    var canShowTranslation: Bool {
        LocalAI.isAvailable || currentStock.has_translation
    }

    var deleteErrorBinding: Binding<Bool> {
        // Why: self(非 Sendable)ではなく $deleteError 自体をキャプチャすることで、
        // Binding の @Sendable クロージャに関する警告を避ける。
        let deleteError = $deleteError
        return Binding(get: { deleteError.wrappedValue != nil }, set: { if !$0 { deleteError.wrappedValue = nil } })
    }

    /// 削除を実行する。失敗時は deleteError に格納する(呼び出し側が dismiss 等の後処理を行う)。
    @MainActor
    func delete() async {
        do {
            try await stockStore.deleteStock(id: currentStock.id)
        } catch {
            deleteError = error
        }
    }
}
