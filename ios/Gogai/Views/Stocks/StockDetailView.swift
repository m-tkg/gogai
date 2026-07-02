import SwiftUI

/// ストックの詳細(タイトル・ストック元・日付・サマリー)。
/// サマリーの4セクション構成表示は StockSummary パーサ導入後に対応する。
struct StockDetailView: View {
    let stock: Stock

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss

    @State private var showBrowser = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: Error?

    private var currentStock: Stock {
        stockStore.stocks.first(where: { $0.id == stock.id }) ?? stock
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(currentStock.title ?? currentStock.url)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    Label(currentStock.source, systemImage: "folder")
                    Label(currentStock.stocked_at.displayDate, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                if let summary = currentStock.summary {
                    Text(summary)
                } else {
                    Label("要約を生成中です…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("ストック")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if URL(string: currentStock.url) != nil {
                    Button {
                        showBrowser = true
                    } label: {
                        Image(systemName: "safari")
                    }
                }
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .navigationDestination(isPresented: $showBrowser) {
            if let url = URL(string: currentStock.url) {
                BrowserView(url: url)
            }
        }
        .sheet(isPresented: $showEdit) {
            EditStockView(stock: currentStock)
        }
        .confirmationDialog("このストックを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await stockStore.deleteStock(id: currentStock.id)
                        dismiss()
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
    }
}
