import SwiftUI

/// ストック一覧の行。長押しで元記事・翻訳・要約生成・編集・削除のコンテキストメニューを表示する
/// (StockDetailView のフッターと同じアクションセット)。削除はスワイプからも実行できる
/// (どちらも同じ確認ダイアログ・エラーハンドリングを共有する)。
struct StockRowView: View {
    let stock: Stock

    @EnvironmentObject private var stockStore: StockStore

    @State private var showBrowser = false
    @State private var showTranslation = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showSummaryErrorAlert = false
    @State private var deleteError: Error?

    private var actions: StockActions {
        StockActions(stockStore: stockStore, fallbackStock: stock, deleteError: $deleteError)
    }

    private var currentStock: Stock { actions.currentStock }
    private var isGeneratingSummary: Bool { actions.isGeneratingSummary }
    private var isQueued: Bool { actions.isQueued }
    private var summaryError: String? { actions.summaryError }
    private var canShowTranslation: Bool { actions.canShowTranslation }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentStock.title ?? currentStock.url)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(currentStock.source)
                Text(currentStock.stocked_at.displayDate)
                if isGeneratingSummary {
                    Label(isQueued ? "順番待ち" : "生成中", systemImage: "sparkles")
                } else if summaryError != nil {
                    Button {
                        showSummaryErrorAlert = true
                    } label: {
                        Label("要約エラー", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else if currentStock.summary == nil {
                    Label("要約待ち", systemImage: "hourglass")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
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
                    stockStore.requestSummary(for: currentStock.id)
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
                BrowserView(url: url, onClose: { showBrowser = false })
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
                Task { await actions.delete() }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除に失敗しました", isPresented: actions.deleteErrorBinding) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError?.localizedDescription ?? "")
        }
        // 一覧を見ている間に失敗した場合は即座にアラートで知らせる。
        // 前回起動時に失敗し永続化されているだけの場合(再起動直後の初回表示など)は自動表示せず、
        // 上のビックリマークをタップした時だけ表示する(スクロール中に次々ポップアップしないようにするため)。
        .onChange(of: summaryError) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                showSummaryErrorAlert = true
            }
        }
        .alert("要約の生成に失敗しました", isPresented: $showSummaryErrorAlert) {
            Button("OK") { stockStore.clearSummaryError(for: currentStock.id) }
        } message: {
            Text(summaryError ?? "")
        }
    }
}
