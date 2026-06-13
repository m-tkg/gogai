import XCTest
import UIKit
@testable import Gogai

/// begin / end の呼び出しを記録するモック
@MainActor
private final class MockAsserter: BackgroundExecutionAsserting {
    var beginCount = 0
    var endCount = 0
    var lastName: String?
    var lastExpirationHandler: (@Sendable () -> Void)?

    func begin(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        beginCount += 1
        lastName = name
        lastExpirationHandler = expirationHandler
        return UIBackgroundTaskIdentifier(rawValue: 42)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        endCount += 1
    }
}

@MainActor
final class BackgroundExecutionTests: XCTestCase {

    func test_run_作業の前にbegin_完了後にendが呼ばれる() async {
        let asserter = MockAsserter()
        var beginCountDuringWork = -1

        let result = await BackgroundExecution.run(name: "test-task", asserter: asserter) {
            beginCountDuringWork = asserter.beginCount
            return "done"
        }

        XCTAssertEqual(result, "done")
        XCTAssertEqual(beginCountDuringWork, 1, "作業中はアサーション取得済み")
        XCTAssertEqual(asserter.lastName, "test-task")
        XCTAssertEqual(asserter.endCount, 1, "完了後に解放される")
    }

    func test_run_作業がthrowしてもendが呼ばれる() async {
        let asserter = MockAsserter()
        struct TestError: Error {}

        do {
            _ = try await BackgroundExecution.run(name: "failing", asserter: asserter) {
                throw TestError()
            }
            XCTFail("エラーが伝播するべき")
        } catch {
            // expected
        }
        XCTAssertEqual(asserter.endCount, 1, "失敗時もアサーションを解放する")
    }

    func test_run_猶予切れハンドラ実行後はendが二重に呼ばれない() async {
        let asserter = MockAsserter()

        _ = await BackgroundExecution.run(name: "expiring", asserter: asserter) {
            // 作業中にシステムの猶予切れが発生したことを再現
            asserter.lastExpirationHandler?()
            return 0
        }
        // 猶予切れで1回解放された後、完了時の解放はスキップされる
        XCTAssertEqual(asserter.endCount, 1, "解放は1回だけ")
    }
}
