import XCTest
@testable import Gogai

@available(iOS 26.0, *)
final class FoundationModelTextGeneratorTests: XCTestCase {
    /// FoundationModels の実際の型(LanguageModelError 等)は Xcode/SDK バージョンによって
    /// 利用できないことがあるため、実物を使わずメッセージ文言だけを模したフェイクで検証する。
    private struct FakeError: Error, CustomStringConvertible {
        let description: String
    }

    func test_shrinkPromptIfContextExceeded_contextSizeExceededを含むエラーはプロンプトを縮める() {
        let prompt = String(repeating: "あ", count: 1000)
        let error = FakeError(description: "contextSizeExceeded(contextSize: 4096, tokenCount: 8192)")

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNotNil(shrunk)
        XCTAssertLessThan(shrunk!.count, prompt.count)
    }

    func test_shrinkPromptIfContextExceeded_旧世代のexceededContextWindowSize表記でも検知する() {
        let prompt = String(repeating: "あ", count: 1000)
        let error = FakeError(description: "exceededContextWindowSize(Context(debugDescription: \"...\"))")

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNotNil(shrunk)
        XCTAssertLessThan(shrunk!.count, prompt.count)
    }

    func test_shrinkPromptIfContextExceeded_関係ないエラーはnilを返す() {
        let prompt = String(repeating: "あ", count: 1000)

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: URLError(.badServerResponse))

        XCTAssertNil(shrunk)
    }

    func test_shrinkPromptIfContextExceeded_縮小後も最低限の長さを保つ() {
        let prompt = String(repeating: "あ", count: 300)
        let error = FakeError(description: "contextSizeExceeded")

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNotNil(shrunk)
        XCTAssertGreaterThanOrEqual(shrunk!.count, 200)
    }

    func test_shrinkPromptIfContextExceeded_これ以上縮められない短さならnilを返す() {
        let prompt = String(repeating: "あ", count: 150)
        let error = FakeError(description: "contextSizeExceeded")

        let shrunk = FoundationModelTextGenerator.shrinkPromptIfContextExceeded(prompt, error: error)

        XCTAssertNil(shrunk)
    }
}
