import XCTest
@testable import Gogai

final class HorizontalSwipeTests: XCTestCase {
    func test_左スワイプ_左への大きな横移動で成立する() {
        XCTAssertTrue(HorizontalSwipe.left.matches(CGSize(width: -100, height: 10)))
        XCTAssertTrue(HorizontalSwipe.left.matches(CGSize(width: -81, height: 0)))
    }

    func test_左スワイプ_閾値未満や右方向では成立しない() {
        XCTAssertFalse(HorizontalSwipe.left.matches(CGSize(width: -79, height: 0)), "80pt 未満は不成立")
        XCTAssertFalse(HorizontalSwipe.left.matches(CGSize(width: 100, height: 0)), "右方向は不成立")
    }

    func test_左スワイプ_縦成分が大きい場合はスクロールとみなして不成立() {
        XCTAssertFalse(HorizontalSwipe.left.matches(CGSize(width: -100, height: 60)),
                       "縦成分が横の半分以上なら不成立")
        XCTAssertTrue(HorizontalSwipe.left.matches(CGSize(width: -100, height: -49)),
                      "縦成分が横の半分未満なら成立（符号は問わない）")
    }

    func test_右スワイプ_右への大きな横移動で成立する() {
        XCTAssertTrue(HorizontalSwipe.right.matches(CGSize(width: 100, height: -10)))
        XCTAssertFalse(HorizontalSwipe.right.matches(CGSize(width: -100, height: 0)))
        XCTAssertFalse(HorizontalSwipe.right.matches(CGSize(width: 100, height: 90)))
    }
}
