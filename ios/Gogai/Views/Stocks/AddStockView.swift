import SwiftUI

struct AddStockView: View {
    @EnvironmentObject private var stockStore: StockStore

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var sourceText = ""
    @State private var categoryText = ""
    @State private var categoryEditedManually = false

    var body: some View {
        FormSheet(
            title: "ストックを追加",
            confirmLabel: "追加",
            confirmDisabled: urlText.trimmingCharacters(in: .whitespaces).isEmpty,
            onSubmit: {
                let url = urlText.trimmingCharacters(in: .whitespaces)
                let title = titleText.trimmingCharacters(in: .whitespaces)
                let source = sourceText.trimmingCharacters(in: .whitespaces)
                let category = categoryText.trimmingCharacters(in: .whitespaces)
                try await stockStore.createStock(
                    url: url,
                    title: title.isEmpty ? nil : title,
                    source: source.isEmpty ? nil : source,
                    category: category.isEmpty ? nil : category
                )
            }
        ) {
            Section("URL") {
                TextField("https://example.com/article", text: $urlText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section("タイトル（任意）") {
                TextField("タイトル", text: $titleText)
            }
            Section("ストック元（任意）") {
                TextField("例: Tech", text: $sourceText)
                    .onChange(of: sourceText) { _, newValue in
                        // カテゴリを未編集ならストック元の入力に追従させる
                        guard !categoryEditedManually else { return }
                        categoryText = newValue
                    }
            }
            Section("カテゴリ（任意・初期値はストック元と同じ）") {
                TextField("例: あとで読む", text: $categoryText)
                    .onChange(of: categoryText) { _, _ in
                        categoryEditedManually = true
                    }
            }
        }
    }
}
