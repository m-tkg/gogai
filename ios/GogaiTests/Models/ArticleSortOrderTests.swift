import XCTest
@testable import Gogai

final class ArticleSortOrderTests: XCTestCase {
    func test_badgeIconName_publishedAt_returnsRss() {
        XCTAssertEqual(ArticleSortOrder.publishedAt.badgeIconName, "rss")
    }

    func test_badgeIconName_readAt_returnsEnvelopeOpen() {
        XCTAssertEqual(ArticleSortOrder.readAt.badgeIconName, "envelope.open")
    }
}
