import XCTest
@testable import Gogai

final class ArticleSortOrderTests: XCTestCase {
    func test_badgeIconName_publishedAt_returnsRss() {
        XCTAssertEqual(ArticleSortOrder.publishedAt.badgeIconName, "rss")
    }

    func test_badgeIconName_readAt_returnsEnvelopeOpen() {
        XCTAssertEqual(ArticleSortOrder.readAt.badgeIconName, "envelope.open")
    }

    func test_badgeIconName_allCasesAreNonEmpty() {
        for order in ArticleSortOrder.allCases {
            XCTAssertFalse(order.badgeIconName.isEmpty, "\(order) の badgeIconName が空です")
        }
    }
}
