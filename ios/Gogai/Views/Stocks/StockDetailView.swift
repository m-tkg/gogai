import SwiftUI

/// サマリーの4セクション(何についての記事か/何の目的で書かれたか/
/// 筆者が一番伝えたいこと/要約)を表示する。パース失敗時は生テキストにフォールバックする。
private struct StockSummarySections: View {
    let summary: String

    var body: some View {
        if let parsed = StockSummary.parse(summary) {
            VStack(alignment: .leading, spacing: 16) {
                section(title: "何についての記事か", body: parsed.topic)
                section(title: "何の目的で書かれたか", body: parsed.purpose)
                section(title: "筆者が一番伝えたいこと", body: parsed.mainMessage)
                VStack(alignment: .leading, spacing: 4) {
                    Text("要約")
                        .font(.headline)
                    ForEach(Array(parsed.summaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
            }
        } else {
            Text(summary)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
        }
    }
}

/// ストックの詳細(タイトル・ストック元・日付・サマリー)。
struct StockDetailView: View {
    let stock: Stock

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss

    @State private var showBrowser = false
    @State private var showTranslation = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: Error?

    /// 翻訳を実行できる(または結果を再確認できる)条件:
    /// この端末で AI が使えるか、既に翻訳済みで結果が保存されているか
    private var canShowTranslation: Bool {
        LocalAI.isAvailable || currentStock.has_translation
    }

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
                    StockSummarySections(summary: summary)
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
                    if canShowTranslation {
                        Button {
                            showTranslation = true
                        } label: {
                            Image(systemName: "character.bubble")
                        }
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
