import SwiftUI

struct SwipeAction {
    let systemImage: String
    let tint: Color
    let action: () -> Void
}

/// カスタムスワイプジェスチャー
/// - 12.5% でアイコン表示
/// - 25% で指を離したときにアクション実行
struct SwipeRowModifier: ViewModifier {
    let leading: SwipeAction?
    let trailing: SwipeAction?

    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontal: Bool? = nil  // nil=未確定, true=横方向, false=縦方向

    private let screenWidth = UIScreen.main.bounds.width
    private var showThreshold: CGFloat { screenWidth * 0.125 }
    private var confirmThreshold: CGFloat { screenWidth * 0.25 }

    private var activeAction: SwipeAction? {
        if dragOffset > 0 { return leading }
        if dragOffset < 0 { return trailing }
        return nil
    }
    private var absOffset: CGFloat { abs(dragOffset) }
    private var pastConfirm: Bool { absOffset >= confirmThreshold }

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .background(alignment: dragOffset >= 0 ? .leading : .trailing) {
                if let action = activeAction {
                    action.tint
                        .frame(width: absOffset)
                        .overlay {
                            if absOffset >= showThreshold {
                                Image(systemName: action.systemImage)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .scaleEffect(pastConfirm ? 1.3 : 1.0)
                                    .animation(
                                        .spring(response: 0.2, dampingFraction: 0.6),
                                        value: pastConfirm
                                    )
                            }
                        }
                }
            }
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        let h = abs(value.translation.width)
                        let v = abs(value.translation.height)

                        // 最初の移動方向を確定させる
                        if isHorizontal == nil {
                            guard h > 5 || v > 5 else { return }
                            isHorizontal = h > v * 1.2
                        }
                        guard isHorizontal == true else { return }

                        let t = value.translation.width
                        // アクションのない方向へのスワイプは無視
                        guard (t > 0 && leading != nil) || (t < 0 && trailing != nil) else { return }

                        // confirmThreshold を超えたらゴムバンド抵抗
                        let absT = abs(t)
                        if absT > confirmThreshold {
                            let excess = absT - confirmThreshold
                            let clamped = confirmThreshold + excess * 0.15
                            dragOffset = t > 0 ? clamped : -clamped
                        } else {
                            dragOffset = t
                        }
                    }
                    .onEnded { value in
                        let t = value.translation.width
                        let shouldExecute = abs(t) >= confirmThreshold && isHorizontal == true
                        let isLeading = t > 0
                        isHorizontal = nil

                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }

                        if shouldExecute {
                            if isLeading { leading?.action() }
                            else { trailing?.action() }
                        }
                    }
            )
    }
}
