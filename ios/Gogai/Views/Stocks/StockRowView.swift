import SwiftUI

/// ストック一覧の行。長押しで元記事・翻訳・要約生成・編集・削除のコンテキストメニューを表示する
/// (StockDetailView のフッターと同じアクションセット)。
struct StockRowView: View {
    let stock: Stock

    @EnvironmentObject private var stockStore: StockStore

    @State private var showBrowser = false
    @State private var showTranslation = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: Error?
    @State private var isGeneratingSummary = false
    @State private var summaryError: Error?

    private var currentStock: Stock {
        stockStore.stocks.first(where: { $0.id == stock.id }) ?? stock
    }

    /// 翻訳を実行できる(または結果を再確認できる)条件:
    /// この端末で AI が使えるか、既に翻訳済みで結果が保存されているか
    private var canShowTranslation: Bool {
        LocalAI.isAvailable || currentStock.has_translation
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var summaryErrorBinding: Binding<Bool> {
        Binding(get: { summaryError != nil }, set: { if !$0 { summaryError = nil } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentStock.title ?? currentStock.url)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(currentStock.source)
                Text(currentStock.stocked_at.displayDate)
                if isGeneratingSummary {
                    Label("生成中", systemImage: "sparkles")
                } else if currentStock.summary == nil {
                    Label("要約待ち", systemImage: "hourglass")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contextMenu {
            if URL(string: currentStock.url) != nil {
                Button {
                    showBrowser = true
                } label: {
                    Label("元記事を開く", systemImage: "safari")
                }
            }
            if canShowTranslation {
                Button {
                    showTranslation = true
                } label: {
                    Label("翻訳", systemImage: "character.bubble")
                }
            }
            if currentStock.summary == nil {
                Button {
                    Task { await generateSummary() }
                } label: {
                    Label("要約を生成", systemImage: "sparkles")
                }
                .disabled(isGeneratingSummary || !LocalAI.isAvailable)
            }
            Button {
                showEdit = true
            } label: {
                Label("編集", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .navigationDestination(isPresented: $showBrowser) {
            if let url = URL(string: currentStock.url) {
                BrowserView(url: url)
            }
        }
        .navigationDestination(isPresented: $showTranslation) {
            FMTranslatedPageView(stock: currentStock)
        }
        .sheet(isPresented: $showEdit) {
            EditStockView(stock: currentStock)
        }
        .confirmationDialog("このストックを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await stockStore.deleteStock(id: currentStock.id)
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

    private func generateSummary() async {
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }
        do {
            try await stockStore.generateSummary(for: currentStock.id)
        } catch {
            summaryError = error
        }
    }
}
