import SwiftUI

/// ストック一覧の行。長押しで元記事・翻訳・要約生成・編集・削除のコンテキストメニューを表示する
/// (StockDetailView のフッターと同じアクションセット)。削除はスワイプからも実行できる。
///
/// 削除確認ダイアログは行ではなく親(StockListView)が保持する: `.swipeActions` のボタンで
/// 行内の `@State` を true にして同じ行に確認ダイアログを付けると、スワイプ UI が畳まれる
/// アニメーションと競合してダイアログが一瞬表示されただけで消えてしまう(SwiftUI の既知の挙動)。
/// 行の外側で状態を持つことでこの競合を避ける。
struct StockRowView: View {
    let stock: Stock
    /// 削除確認を親に委譲する(理由は上記コメント参照)。
    let onDeleteRequest: () -> Void

    @EnvironmentObject private var stockStore: StockStore

    @State private var showBrowser = false
    @State private var showTranslation = false
    @State private var showEdit = false
    @State private var showSummaryErrorAlert = false

    private var actions: StockActions {
        StockActions(stockStore: stockStore, fallbackStock: stock, deleteError: .constant(nil))
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
            // role: .destructive にすると、確認を挟む前にタップした時点で SwiftUI が
            // 行をリストから消すアニメーションを実行してしまう(キャンセルしても復活は
            // 次の再読み込みまで反映されない見た目になる)。確認前に消えて見えるのを防ぐため
            // role は付けず、見た目だけ .tint(.red) で destructive 風にする。
            Button {
                onDeleteRequest()
            } label: {
                Label("削除", systemImage: "trash")
            }
            .tint(.red)
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
                onDeleteRequest()
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
