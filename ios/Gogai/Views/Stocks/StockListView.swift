import SwiftUI

/// カテゴリ内のストック一覧。stocked_at でソートし、昇順/降順は端末に永続化する。
struct StockListView: View {
    let category: StockCategory

    @EnvironmentObject private var stockStore: StockStore
    @State private var pendingDeleteOffsets: IndexSet?

    private var stocks: [Stock] { stockStore.stocks(in: category.id) }

    private var showDeleteConfirmBinding: Binding<Bool> {
        Binding(get: { pendingDeleteOffsets != nil }, set: { if !$0 { pendingDeleteOffsets = nil } })
    }

    var body: some View {
        List {
            ForEach(stocks) { stock in
                NavigationLink(value: stock) {
                    StockRowView(stock: stock)
                }
            }
            .onDelete { offsets in
                pendingDeleteOffsets = offsets
            }
        }
        // ネイティブのスワイプ削除は誤操作での一発削除を招くため、長押しメニュー削除と同じく確認を挟む
        .confirmationDialog("このストックを削除しますか？", isPresented: showDeleteConfirmBinding, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let offsets = pendingDeleteOffsets else { return }
                let targets = offsets.map { stocks[$0] }
                Task {
                    for stock in targets {
                        try? await stockStore.deleteStock(id: stock.id)
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
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
    }
}
