import SwiftUI

struct FilterFooterView: View {
    @Binding var filter: ArticleFilter
    /// 指定するとストックボタンを右端に表示する(ストック一覧への遷移用。フィルターではない)
    var onStockTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // 3 つ並ぶとラベル付きでは横幅が足りないためアイコンのみにする
            ForEach(ArticleFilter.allCases, id: \.self) { candidate in
                Button {
                    filter = candidate
                } label: {
                    Image(systemName: candidate.iconName)
                }
                .buttonStyle(.bordered)
                .tint(filter == candidate ? .accentColor : nil)
                .accessibilityLabel(candidate.label)
            }

            Spacer()

            if let onStockTap {
                Button(action: onStockTap) {
                    Image(systemName: "tray.full")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("ストック")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
