import SwiftUI

extension View {
    /// StockCategoryListView → StockListView → StockDetailView の3段の遷移を登録する。
    /// RootView の iPad(fullScreenCover 内)・iPhone(NavigationStack 内)の両方から
    /// StockCategoryListView に対して呼ぶ。
    func stockDestinations() -> some View {
        navigationDestination(for: StockCategory.self) { category in
            StockListView(category: category)
                .navigationDestination(for: Stock.self) { stock in
                    StockDetailView(stock: stock)
                }
        }
    }
}
