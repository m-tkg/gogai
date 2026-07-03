import SwiftUI

struct FilterFooterView: View {
    @Binding var unreadOnly: Bool
    /// 指定するとストックボタンを右端に表示する(ストック一覧への遷移用。フィルターではない)
    var onStockTap: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("全て") {
                    unreadOnly = false
                }
                .buttonStyle(.bordered)
                .tint(!unreadOnly ? .accentColor : nil)

                Button("未読のみ") {
                    unreadOnly = true
                }
                .buttonStyle(.bordered)
                .tint(unreadOnly ? .accentColor : nil)

                if let onStockTap {
                    Divider()
                        .frame(height: 20)

                    Button(action: onStockTap) {
                        Label("ストック", systemImage: "tray.full")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
