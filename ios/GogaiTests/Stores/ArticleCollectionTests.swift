import XCTest
@testable import Gogai

final class ArticleCollectionTests: XCTestCase {
    private func makeArticle(id: Int, feedId: Int = 1, isRead: Int = 0) -> Article {
        Article(id: id, feed_id: feedId, guid: "guid-\(id)", title: "Title \(id)",
                link: nil, summary: nil, content: nil, published_at: nil,
                is_read: isRead, is_favorite: 0, created_at: "2024-01-01T00:00:00Z",
                read_at: nil)
    }

    // MARK: - merge

    func test_merge_isFullFetch_replacesEverything() {
        var collection = ArticleCollection()
        collection.merge([makeArticle(id: 1, feedId: 1), makeArticle(id: 2, feedId: 2)], isFullFetch: true)
        collection.merge([makeArticle(id: 3, feedId: 3)], isFullFetch: true)
        XCTAssertEqual(collection.articles.map { $0.id }, [3])
    }

    func test_merge_partialFetch_replacesOnlyFetchedFeeds() {
        var collection = ArticleCollection()
        collection.merge([makeArticle(id: 1, feedId: 1), makeArticle(id: 2, feedId: 2)], isFullFetch: true)
        collection.merge([makeArticle(id: 10, feedId: 1)], isFullFetch: false)

        XCTAssertEqual(Set(collection.articles.map { $0.id }), [2, 10],
                       "フェッチ結果に含まれるフィードのみ差し替え、他は保持")
    }

    func test_merge_partialFetch_emptyResult_keepsExisting() {
        var collection = ArticleCollection()
        collection.merge([makeArticle(id: 1, feedId: 1)], isFullFetch: true)
        // 空の部分フェッチは何も差し替えない（fetchedFeedIds が空のため）
        collection.merge([], isFullFetch: false)
        XCTAssertEqual(collection.articles.map { $0.id }, [1])
    }

    // MARK: - upsert / updateAll

    func test_upsert_replacesMatchingArticle() {
        var collection = ArticleCollection()
        collection.merge([makeArticle(id: 1, isRead: 0)], isFullFetch: true)
        collection.upsert(makeArticle(id: 1, isRead: 1))
        XCTAssertTrue(collection.articles[0].isRead)
    }

    func test_upsert_unknownId_isIgnored() {
        var collection = ArticleCollection()
        collection.merge([makeArticle(id: 1)], isFullFetch: true)
        collection.upsert(makeArticle(id: 99))
        XCTAssertEqual(collection.articles.count, 1, "未知の記事は追加しない（既存挙動の維持）")
    }

    func test_updateAll_appliesTransformToAllArticles() {
        var collection = ArticleCollection()
        collection.merge([makeArticle(id: 1, isRead: 0), makeArticle(id: 2, isRead: 0)], isFullFetch: true)
        collection.updateAll { $0.updating(isRead: 1) }
        XCTAssertTrue(collection.articles.allSatisfy { $0.isRead })
    }

    // MARK: - replaceAll / isEmpty

    func test_replaceAll_setsArticles() {
        var collection = ArticleCollection()
        collection.replaceAll([makeArticle(id: 5)])
        XCTAssertEqual(collection.articles.map { $0.id }, [5])
    }

    func test_replaceAll_appending_重複idを除いて結合する() {
        var collection = ArticleCollection()
        collection.replaceAll(
            [makeArticle(id: 1), makeArticle(id: 2)],
            appending: [makeArticle(id: 2), makeArticle(id: 99)]
        )
        XCTAssertEqual(collection.articles.map { $0.id }, [1, 2, 99],
                       "本体に既にある id は追加せず、ない id のみ末尾に足す")
    }

    func test_replaceAll_appending_空の追加分でも動く() {
        var collection = ArticleCollection()
        collection.replaceAll([makeArticle(id: 1)], appending: [])
        XCTAssertEqual(collection.articles.map { $0.id }, [1])
    }

    func test_isEmpty() {
        var collection = ArticleCollection()
        XCTAssertTrue(collection.isEmpty)
        collection.replaceAll([makeArticle(id: 1)])
        XCTAssertFalse(collection.isEmpty)
    }
}
