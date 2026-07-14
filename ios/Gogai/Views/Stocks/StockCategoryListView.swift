import SwiftUI

/// 要約キュー(生成中 + 待機中)の一覧をトグル開閉で表示するセクション。
/// 一時停止/再開・個別キャンセルの操作もここに含む。
private struct SummaryQueueSection: View {
    let items: [(id: Int, title: String, isGenerating: Bool)]
    @Binding var isExpanded: Bool
    let isPausedByUser: Bool
    let onCancel: (Int) -> Void
    let onTogglePause: () -> Void

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 8) {
                        if item.isGenerating {
                            ProgressView()
                        } else {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.secondary)
                        }
                        Text(item.title)
                            .lineLimit(1)
                        Spacer()
                        Text(item.isGenerating ? "生成中" : "順番待ち")
                            .foregroundStyle(.secondary)
                        Button {
                            onCancel(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
            } label: {
                HStack {
                    Text("要約キュー (\(items.count))")
                    if isPausedByUser {
                        Text("一時停止中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onTogglePause()
                    } label: {
                        Image(systemName: isPausedByUser ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// ストックのカテゴリ(フォルダ)一覧。タップすると StockListView へ遷移する。
struct StockCategoryListView: View {
    /// true の場合、閉じるボタンを表示する(iPad の fullScreenCover 表示用)
    var isModal: Bool = false

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showAddStock = false
    @State private var showLocalAIUnavailableAlert = false
    @State private var isQueueExpanded = true
    @State private var reorderError: Error?
    /// 初回表示のみフェッチするためのガード。StockListView から戻る際は再フェッチしない
    /// (ArticleListView の hasAppeared と同じパターン)。
    @State private var hasAppeared = false

    private var reorderErrorBinding: Binding<Bool> {
        Binding(
            get: { reorderError != nil },
            set: { if !$0 { reorderError = nil } }
        )
    }

    /// 現在生成中 + 待機中を合わせた要約キューの一覧(表示用)。
    private var summaryQueueItems: [(id: Int, title: String, isGenerating: Bool)] {
        var items: [(id: Int, title: String, isGenerating: Bool)] = []
        if let currentId = stockStore.currentlySummarizingStockId {
            items.append((currentId, title(for: currentId), true))
        }
        items += stockStore.pendingSummaryStockIds.map { (id: $0, title: title(for: $0), isGenerating: false) }
        return items
    }

    private func title(for stockId: Int) -> String {
        stockStore.stocks.first(where: { $0.id == stockId })?.title ?? "記事"
    }

    /// まだ要約がないストックの ID(一括要約の対象)
    private var unsummarizedStockIds: [Int] {
        stockStore.stocks.filter { $0.summary == nil }.map(\.id)
    }

    private func summarizeAllUnsummarized() {
        guard LocalAI.isAvailable else {
            showLocalAIUnavailableAlert = true
            return
        }
        for id in unsummarizedStockIds {
            stockStore.requestSummary(for: id)
        }
    }

    /// カテゴリ内のいずれかのストックで要約エラーが発生しているか(赤いビックリマーク表示用)
    private func categoryHasSummaryError(_ category: StockCategory) -> Bool {
        stockStore.stocks.contains { $0.category_id == category.id && stockStore.summaryErrors[$0.id] != nil }
    }

    var body: some View {
        List {
            if !unsummarizedStockIds.isEmpty {
                Button {
                    summarizeAllUnsummarized()
                } label: {
                    Label("未要約のものを一括要約", systemImage: "sparkles")
                }
            }
            if !summaryQueueItems.isEmpty {
                SummaryQueueSection(
                    items: summaryQueueItems,
                    isExpanded: $isQueueExpanded,
                    isPausedByUser: stockStore.isSummaryQueuePausedByUser,
                    onCancel: { stockStore.cancelSummary(for: $0) },
                    onTogglePause: {
                        if stockStore.isSummaryQueuePausedByUser {
                            stockStore.resumeSummaryQueue()
                        } else {
                            stockStore.pauseSummaryQueue()
                        }
                    }
                )
            }
            ForEach(stockStore.categories) { category in
                NavigationLink(value: category) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(category.name)
                        if categoryHasSummaryError(category) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(category.stock_count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { from, to in
                Task {
                    do {
                        try await stockStore.reorderCategories(from: from, to: to)
                    } catch {
                        reorderError = error
                    }
                }
            }
        }
        .navigationTitle("ストック")
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(isEditing ? "完了" : "編集") { isEditing.toggle() }
                Button {
                    showAddStock = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if stockStore.categories.isEmpty {
                ContentUnavailableView("ストックがありません", systemImage: "tray")
            }
        }
        .task {
            // 初回表示のみフェッチする(StockListView から戻る際に全件再フェッチしてリストが
            // 一瞬リセットされるのを防ぐ)。手動更新は .refreshable 側で常にフェッチする。
            guard !hasAppeared else { return }
            hasAppeared = true
            await stockStore.fetchAll()
        }
        .refreshable {
            await stockStore.fetchAll()
        }
        .sheet(isPresented: $showAddStock) {
            AddStockView()
        }
        .alert("並び替えエラー", isPresented: reorderErrorBinding) {
            Button("OK") { reorderError = nil }
        } message: {
            Text(reorderError?.localizedDescription ?? "")
        }
        .alert("要約を生成できません", isPresented: $showLocalAIUnavailableAlert) {
            Button("OK") { showLocalAIUnavailableAlert = false }
        } message: {
            Text(LocalAI.unavailableReason ?? "ローカル AI が利用できません。")
        }
    }
}
