import XCTest
@testable import Gogai

final class LocalAIErrorTests: XCTestCase {
    func test_aiUnavailable_端末非対応の説明文を返す() {
        XCTAssertEqual(
            LocalAIError.aiUnavailable.errorDescription,
            "この端末ではローカル AI を利用できません(iOS 27 以上と Apple Intelligence の有効化が必要です)"
        )
    }

    func test_invalidURL_URL不正の説明文を返す() {
        XCTAssertEqual(LocalAIError.invalidURL.errorDescription, "URL が不正です")
    }

    func test_emptyContent_本文空の説明文を返す() {
        XCTAssertNotNil(LocalAIError.emptyContent.errorDescription)
    }

    func test_parseFailed_解析失敗の説明文を返す() {
        XCTAssertNotNil(LocalAIError.parseFailed.errorDescription)
    }

    func test_Equatable準拠() {
        XCTAssertEqual(LocalAIError.emptyContent, LocalAIError.emptyContent)
        XCTAssertNotEqual(LocalAIError.emptyContent, LocalAIError.parseFailed)
    }
}
