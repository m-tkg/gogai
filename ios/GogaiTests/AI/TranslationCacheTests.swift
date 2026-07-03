import XCTest
@testable import Gogai

@MainActor
final class TranslationCacheTests: XCTestCase {
    private var tmpDir: URL!
    private var cache: TranslationCache!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cache = TranslationCache(directory: tmpDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func test_storeした訳文をsourceで引ける() {
        cache.store(source: "Hello", target: "こんにちは", engine: .translationFramework)
        XCTAssertEqual(cache.target(for: "Hello", engine: .translationFramework), "こんにちは")
    }

    func test_未登録のsourceはnil() {
        XCTAssertNil(cache.target(for: "Unknown", engine: .translationFramework))
    }

    func test_エンジンが異なればキャッシュは別物() {
        cache.store(source: "Hello", target: "システム訳", engine: .translationFramework)
        XCTAssertNil(cache.target(for: "Hello", engine: .foundationModel),
                     "基盤モデルの訳としては引けない")
    }

    func test_1週間経過したエントリは失効する() {
        let now = Date()
        cache.store(source: "Hello", target: "こんにちは", engine: .translationFramework, now: now)

        let within = now.addingTimeInterval(TranslationCache.timeToLive - 60)
        XCTAssertEqual(cache.target(for: "Hello", engine: .translationFramework, now: within), "こんにちは")

        let expired = now.addingTimeInterval(TranslationCache.timeToLive + 60)
        XCTAssertNil(cache.target(for: "Hello", engine: .translationFramework, now: expired),
                     "1週間を過ぎたら失効する")
    }

    func test_ディスクに永続化され別インスタンスから読める() {
        cache.store(source: "Hello", target: "こんにちは", engine: .translationFramework)
        cache.persist()

        let reloaded = TranslationCache(directory: tmpDir)
        XCTAssertEqual(reloaded.target(for: "Hello", engine: .translationFramework), "こんにちは")
    }

    func test_persist時に失効エントリは破棄される() {
        let old = Date().addingTimeInterval(-TranslationCache.timeToLive - 60)
        cache.store(source: "Old", target: "古い訳", engine: .translationFramework, now: old)
        cache.store(source: "New", target: "新しい訳", engine: .translationFramework)
        cache.persist()

        let reloaded = TranslationCache(directory: tmpDir)
        XCTAssertNil(reloaded.target(for: "Old", engine: .translationFramework))
        XCTAssertEqual(reloaded.target(for: "New", engine: .translationFramework), "新しい訳")
    }
}
