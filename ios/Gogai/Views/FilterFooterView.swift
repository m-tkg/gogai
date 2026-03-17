import SwiftUI

struct FilterFooterView: View {
    @Binding var unreadOnly: Bool
    @Binding var summaryOnly: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button("全て") {
                unreadOnly = false
                summaryOnly = false
            }
            .buttonStyle(.bordered)
            .tint(!unreadOnly && !summaryOnly ? .accentColor : nil)

            Button("未読のみ") {
                unreadOnly = true
                summaryOnly = false
            }
            .buttonStyle(.bordered)
            .tint(unreadOnly ? .accentColor : nil)

            Button("要約あり") {
                summaryOnly = true
                unreadOnly = false
            }
            .buttonStyle(.bordered)
            .tint(summaryOnly ? .accentColor : nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
