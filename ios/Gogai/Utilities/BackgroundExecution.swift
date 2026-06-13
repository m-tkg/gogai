import UIKit

/// バックグラウンド遷移後も処理を継続するための実行アサーション発行者。
/// 本番は UIApplication、テストはモックを注入する。
@MainActor
protocol BackgroundExecutionAsserting {
    func begin(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: BackgroundExecutionAsserting {
    func begin(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        endBackgroundTask(identifier)
    }
}

/// 要約・翻訳などの実行中にユーザーがアプリをバックグラウンドへ移しても、
/// システムの猶予（最大約30秒）内で処理を継続させるためのヘルパー。
enum BackgroundExecution {
    /// work の実行中、バックグラウンドタスク・アサーションを保持する。
    /// 完了・エラー・猶予切れのいずれでも確実に1回だけ解放する。
    @MainActor
    static func run<T>(
        name: String,
        asserter: any BackgroundExecutionAsserting = UIApplication.shared,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let token = Token(name: name, asserter: asserter)
        defer { token.release() }
        return try await work()
    }

    /// アサーションの取得と1回限りの解放を管理する
    @MainActor
    private final class Token {
        private var identifier: UIBackgroundTaskIdentifier = .invalid
        private let asserter: any BackgroundExecutionAsserting

        init(name: String, asserter: any BackgroundExecutionAsserting) {
            self.asserter = asserter
            identifier = asserter.begin(name: name) { [weak self] in
                // expirationHandler はメインスレッドで呼ばれる（UIApplication の仕様）
                MainActor.assumeIsolated {
                    self?.release()
                }
            }
        }

        func release() {
            guard identifier != .invalid else { return }
            asserter.end(identifier)
            identifier = .invalid
        }
    }
}
