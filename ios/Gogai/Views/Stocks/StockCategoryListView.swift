import SwiftUI

/// ストックのカテゴリ(フォルダ)一覧。タップすると StockListView へ遷移する。
struct StockCategoryListView: View {
    /// true の場合、閉じるボタンを表示する(iPad の fullScreenCover 表示用)
    var isModal: Bool = false

    @EnvironmentObject private var stockStore: StockStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showAddStock = false

    var body: some View {
        List {
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
