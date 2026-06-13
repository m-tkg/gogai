import SwiftUI

/// 横スワイプの方向と成立判定。
/// 「横に80pt超 かつ 縦成分が横成分の半分未満（スクロールと区別）」で成立する。
enum HorizontalSwipe {
    case left
    case right

    static let minimumDistance: CGFloat = 80

    func matches(_ translation: CGSize) -> Bool {
        let horizontal = translation.width
        let directionOK: Bool
        switch self {
        case .left: directionOK = horizontal < -Self.minimumDistance
        case .right: directionOK = horizontal > Self.minimumDistance
        }
        return directionOK && abs(translation.height) < abs(horizontal) * 0.5
    }
}

extension View {
    /// 指定方向の横スワイプで action を実行する（縦スクロールとは共存）
    func onHorizontalSwipe(_ direction: HorizontalSwipe, perform action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: HorizontalSwipe.minimumDistance, coordinateSpace: .local)
                .onEnded { value in
                    if direction.matches(value.translation) {
                        action()
                    }
                }
        )
    }
}
