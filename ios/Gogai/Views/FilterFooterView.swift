import SwiftUI

struct FilterFooterView: View {
    @Binding var unreadOnly: Bool
    @Binding var summaryOnly: Bool
    @Binding var favoriteOnly: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("全て") {
                    unreadOnly = false
                    summaryOnly = false
                    favoriteOnly = false
                }
                .buttonStyle(.bordered)
                .tint(!unreadOnly && !summaryOnly && !favoriteOnly ? .accentColor : nil)

                Button("未読のみ") {
                    unreadOnly = true
                    summaryOnly = false
                    favoriteOnly = false
                }
                .buttonStyle(.bordered)
                .tint(unreadOnly ? .accentColor : nil)

                Button("要約あり") {
                    summaryOnly = true
                    unreadOnly = false
                    favoriteOnly = false
                }
                .buttonStyle(.bordered)
                .tint(summaryOnly ? .accentColor : nil)

                Button {
                    favoriteOnly = true
                    unreadOnly = false
                    summaryOnly = false
                } label: {
                    Label("お気に入り", systemImage: "star.fill")
                }
                .buttonStyle(.bordered)
                .tint(favoriteOnly ? .yellow : nil)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
