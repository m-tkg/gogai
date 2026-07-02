import SwiftUI

/// カテゴリ内のストック一覧。stocked_at でソートし、昇順/降順は端末に永続化する。
struct StockListView: View {
    let category: StockCategory

    @EnvironmentObject private var stockStore: StockStore

    private var stocks: [Stock] { stockStore.stocks(in: category.id) }

    var body: some View {
        List {
            ForEach(stocks) { stock in
                NavigationLink(value: stock) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stock.title ?? stock.url)
                            .font(.body)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(stock.source)
                            Text(stock.stocked_at.displayDate)
                            if stock.summary == nil {
                                Label("要約待ち", systemImage: "hourglass")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let targets = offsets.map { stocks[$0] }
                Task {
                    for stock in targets {
                        try? await stockStore.deleteStock(id: stock.id)
                    }
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
    }
}
