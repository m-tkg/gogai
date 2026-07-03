import SwiftUI

/// ストックのカテゴリ(フォルダ)一覧。タップすると StockListView へ遷移する。
struct StockCategoryListView: View {
    /// true の場合、閉じるボタンを表示する(iPad の fullScreenCover 表示用)
    var isModal: Bool = false

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showAddStock = false

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

    var body: some View {
        List {
            if !summaryQueueItems.isEmpty {
                Section("要約キュー") {
                    ForEach(summaryQueueItems, id: \.id) { item in
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
                        }
                        .font(.subheadline)
                    }
                }
            }
            ForEach(stockStore.categories) { category in
                NavigationLink(value: category) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(category.name)
                        Spacer()
                        Text("\(category.stock_count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { from, to in
                Task { try? await stockStore.reorderCategories(from: from, to: to) }
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
            await stockStore.fetchAll()
        }
        .refreshable {
            await stockStore.fetchAll()
        }
        .sheet(isPresented: $showAddStock) {
            AddStockView()
        }
    }
}
