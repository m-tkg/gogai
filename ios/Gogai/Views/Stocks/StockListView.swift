import SwiftUI

/// カテゴリ内のストック一覧。stocked_at でソートし、昇順/降順は端末に永続化する。
struct StockListView: View {
    let category: StockCategory

    @EnvironmentObject private var stockStore: StockStore

    /// 削除確認の対象。StockRowView ではなくここで保持する理由は StockRowView 側のコメント参照。
    @State private var stockPendingDelete: Stock?
    @State private var deleteError: Error?

    private var stocks: [Stock] { stockStore.stocks(in: category.id) }

    private var isDeleteConfirmPresented: Binding<Bool> {
        Binding(get: { stockPendingDelete != nil }, set: { if !$0 { stockPendingDelete = nil } })
    }

    var body: some View {
        List {
            ForEach(stocks) { stock in
                NavigationLink(value: stock) {
                    StockRowView(stock: stock, onDeleteRequest: { stockPendingDelete = stock })
                }
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    stockStore.sortAscending.toggle()
                } label: {
                    Image(systemName: stockStore.sortAscending ? "arrow.up" : "arrow.down")
                }
            }
        }
        .overlay {
            if stocks.isEmpty {
                ContentUnavailableView("ストックがありません", systemImage: "tray")
            }
        }
        .refreshable {
            await stockStore.fetchAll()
        }
        .alert("このストックを削除しますか？", isPresented: isDeleteConfirmPresented) {
            Button("削除", role: .destructive) {
                if let stock = stockPendingDelete {
                    Task { await delete(stock) }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除に失敗しました", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError?.localizedDescription ?? "")
        }
    }

    @MainActor
    private func delete(_ stock: Stock) async {
        let actions = StockActions(stockStore: stockStore, fallbackStock: stock, deleteError: $deleteError)
        await actions.delete()
    }
}
