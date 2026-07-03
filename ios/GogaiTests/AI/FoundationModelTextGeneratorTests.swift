import XCTest
import FoundationModels
@testable import Gogai

@available(iOS 27.0, *)
final class FoundationModelTextGeneratorTests: XCTestCase {
    private func contextSizeExceededError(contextSize: Int, tokenCount: Int) -> Error {
        LanguageModelError.contextSizeExceeded(
            .init(contextSize: contextSize, tokenCount: tokenCount, debugDescription: "test")
        )
    }

    func test_shrinkPromptIfContextExceeded_トークン超過分に応じてプロンプトを縮める() {
        let prompt = String(repeating: "あ", count: 1000)
        let error = contextSizeExceededError(contextSize: 4096, tokenCount: 8192)

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNotNil(shrunk)
        XCTAssertLessThan(shrunk!.count, prompt.count)
    }

    func test_shrinkPromptIfContextExceeded_関係ないエラーはnilを返す() {
        let prompt = String(repeating: "あ", count: 1000)

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: URLError(.badServerResponse))

        XCTAssertNil(shrunk)
    }

    func test_shrinkPromptIfContextExceeded_tokenCountが0以下ならnilを返す() {
        let prompt = String(repeating: "あ", count: 1000)
        let error = contextSizeExceededError(contextSize: 4096, tokenCount: 0)

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNil(shrunk)
    }

    func test_shrinkPromptIfContextExceeded_縮小後も最低限の長さを保つ() {
        let prompt = String(repeating: "あ", count: 300)
        let error = contextSizeExceededError(contextSize: 100, tokenCount: 100_000)

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNotNil(shrunk)
        XCTAssertGreaterThanOrEqual(shrunk!.count, 200)
    }
}
