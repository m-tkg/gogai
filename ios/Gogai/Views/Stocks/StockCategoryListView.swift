import SwiftUI

/// ストックのカテゴリ(フォルダ)一覧。タップすると StockListView へ遷移する。
struct StockCategoryListView: View {
    /// true の場合、閉じるボタンを表示する(iPad の fullScreenCover 表示用)
    var isModal: Bool = false

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showAddStock = false

    /// 要約キューの状態を「「タイトル」を要約中… 他N件待機中」の形で表示する。
    private var summaryQueueBannerText: String? {
        guard let currentId = stockStore.currentlySummarizingStockId else { return nil }
        let title = stockStore.stocks.first(where: { $0.id == currentId })?.title ?? "記事"
        let pendingCount = stockStore.pendingSummaryStockIds.count
        let suffix = pendingCount > 0 ? "… 他\(pendingCount)件待機中" : "…"
        return "「\(title)」を要約中\(suffix)"
    }

    var body: some View {
        List {
            if let banner = summaryQueueBannerText {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(banner)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showAddStock) {
            AddStockView()
        }
    }
}
