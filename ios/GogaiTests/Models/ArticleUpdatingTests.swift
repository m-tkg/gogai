import XCTest
@testable import Gogai

final class ArticleUpdatingTests: XCTestCase {
    private func makeArticle(isRead: Int = 0, readAt: String? = nil) -> Article {
        Article(id: 1, feed_id: 2, guid: "guid", title: "Title",
                link: "https://example.com", summary: "summary", content: "content",
                published_at: "2026-01-01T00:00:00Z", is_read: isRead,
                created_at: "2026-01-01T00:00:00Z", read_at: readAt)
    }

    func test_引数なしは同じ内容を返す() {
        let article = makeArticle(isRead: 1, readAt: "2026-01-02T00:00:00Z")
        XCTAssertEqual(article.updating(), article)
    }

    func test_isReadのみ変更し他のフィールドは保持する() {
        let article = makeArticle(readAt: "2026-01-02T00:00:00Z")
        let updated = article.updating(isRead: 1)
        XCTAssertEqual(updated.is_read, 1)
        XCTAssertEqual(updated.read_at, "2026-01-02T00:00:00Z")
        XCTAssertEqual(updated.id, article.id)
        XCTAssertEqual(updated.title, article.title)
    }

    func test_readAtを設定できる() {
        let article = makeArticle()
        let updated = article.updating(isRead: 1, readAt: .set("2026-06-12T00:00:00Z"))
        XCTAssertEqual(updated.read_at, "2026-06-12T00:00:00Z")
    }

    func test_readAtをクリアできる() {
        let article = makeArticle(isRead: 1, readAt: "2026-01-02T00:00:00Z")
        let updated = article.updating(isRead: 0, readAt: .clear)
        XCTAssertEqual(updated.is_read, 0)
        XCTAssertNil(updated.read_at)
    }

    func test_readAtのデフォルトは既存値を保持する() {
        let article = makeArticle(readAt: "2026-01-02T00:00:00Z")
        let updated = article.updating(isRead: 1)
        XCTAssertEqual(updated.read_at, "2026-01-02T00:00:00Z")
    }
}
