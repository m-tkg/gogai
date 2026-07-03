import SwiftUI

/// ストックの編集。編集できるのはタイトルとカテゴリのみ(ストック元は作成後不変)。
struct EditStockView: View {
    let stock: Stock
    @EnvironmentObject private var stockStore: StockStore

    @State private var titleText: String
    @State private var categoryText: String

    init(stock: Stock) {
        self.stock = stock
        _titleText = State(initialValue: stock.title ?? "")
        _categoryText = State(initialValue: stock.category_name)
    }

    var body: some View {
        FormSheet(
            title: "ストックを編集",
            confirmLabel: "保存",
            confirmDisabled: categoryText.trimmingCharacters(in: .whitespaces).isEmpty,
            onSubmit: {
                let title = titleText.trimmingCharacters(in: .whitespaces)
                let category = categoryText.trimmingCharacters(in: .whitespaces)
                try await stockStore.updateStock(id: stock.id, title: title, category: category)
            }
        ) {
            Section("タイトル") {
                TextField("タイトル", text: $titleText)
            }
            Section("カテゴリ") {
                TextField("カテゴリ", text: $categoryText)
                if !stockStore.categories.isEmpty {
                    Menu("既存のカテゴリから選ぶ") {
                        ForEach(stockStore.categories) { category in
                            Button(category.name) { categoryText = category.name }
                        }
                    }
                }
            }
            Section("ストック元") {
                Text(stock.source)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
