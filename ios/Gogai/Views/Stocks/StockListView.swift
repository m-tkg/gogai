import SwiftUI

/// コンテキストメニューからの push 遷移先。Stock 型をそのまま使うと
/// NavigationLink(value:) の詳細ページ遷移と衝突するため、ラッパー型で区別する
private struct StockBrowserDestination: Hashable {
    let stock: Stock
}

private struct StockTranslationDestination: Hashable {
    let stock: Stock
}

/// カテゴリ内のストック一覧。stocked_at でソートし、昇順/降順は端末に永続化する。
/// 行の長押しで詳細ページのフッターと同じ操作(元記事・翻訳・要約生成・編集・削除)を提供する。
struct StockListView: View {
    let category: StockCategory

    @EnvironmentObject private var stockStore: StockStore

    @State private var browserTarget: StockBrowserDestination?
    @State private var translationTarget: StockTranslationDestination?
    @State private var editingStock: Stock?
    @State private var deletingStock: Stock?
    @State private var generatingSummaryIds: Set<Int> = []
    @State private var deleteError: Error?
    @State private var summaryError: Error?

    private var stocks: [Stock] { stockStore.stocks(in: category.id) }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(get: { deletingStock != nil }, set: { if !$0 { deletingStock = nil } })
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var summaryErrorBinding: Binding<Bool> {
        Binding(get: { summaryError != nil }, set: { if !$0 { summaryError = nil } })
    }

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
                .contextMenu {
                    contextMenuItems(for: stock)
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
        .navigationDestination(item: $browserTarget) { target in
            if let url = URL(string: target.stock.url) {
                BrowserView(url: url)
            }
        }
        .navigationDestination(item: $translationTarget) { target in
            FMTranslatedPageView(stock: target.stock)
        }
        .sheet(item: $editingStock) { stock in
            EditStockView(stock: stock)
        }
        .confirmationDialog("このストックを削除しますか？", isPresented: deleteConfirmBinding, titleVisibility: .visible, presenting: deletingStock) { stock in
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await stockStore.deleteStock(id: stock.id)
                    } catch {
                        deleteError = error
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除に失敗しました", isPresented: deleteErrorBinding) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError?.localizedDescription ?? "")
        }
        .alert("要約の生成に失敗しました", isPresented: summaryErrorBinding) {
            Button("OK") { summaryError = nil }
        } message: {
            Text(summaryError?.localizedDescription ?? "")
        }
    }

    /// 詳細ページ(StockDetailView)のフッターと同じ操作・表示条件をコンテキストメニューで提供する
    @ViewBuilder
    private func contextMenuItems(for stock: Stock) -> some View {
        if URL(string: stock.url) != nil {
            Button {
                browserTarget = StockBrowserDestination(stock: stock)
            } label: {
                Label("元記事", systemImage: "safari")
            }
        }
        if LocalAI.isAvailable || stock.has_translation {
            Button {
                translationTarget = StockTranslationDestination(stock: stock)
            } label: {
                Label("翻訳", systemImage: "character.bubble")
            }
        }
        if stock.summary == nil {
            Button {
                Task { await generateSummary(for: stock) }
            } label: {
                Label("要約を生成", systemImage: "sparkles")
            }
            .disabled(generatingSummaryIds.contains(stock.id) || !LocalAI.isAvailable)
        }
        Button {
            editingStock = stock
        } label: {
            Label("編集", systemImage: "pencil")
        }
        Button(role: .destructive) {
            deletingStock = stock
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    private func generateSummary(for stock: Stock) async {
        generatingSummaryIds.insert(stock.id)
        defer { generatingSummaryIds.remove(stock.id) }
        do {
            try await stockStore.generateSummary(for: stock.id)
        } catch {
            summaryError = error
        }
    }
}
