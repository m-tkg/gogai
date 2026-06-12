import SwiftUI

/// フィード・「すべての記事」行に表示する未読数バッジ（1000 件以上は "1000+"）
struct UnreadCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count >= 1000 ? "1000+" : "\(count)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())
        }
    }
}
