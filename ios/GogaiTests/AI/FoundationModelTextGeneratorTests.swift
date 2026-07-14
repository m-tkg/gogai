import XCTest
@testable import Gogai

@available(iOS 26.0, *)
final class FoundationModelTextGeneratorTests: XCTestCase {
    /// FoundationModels の実際の型(LanguageModelError 等)は Xcode/SDK バージョンによって
    /// 利用できないことがあるため、実物を使わずメッセージ文言だけを模したフェイクで検証する。
    private struct FakeError: Error, CustomStringConvertible {
        let description: String
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
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

    // MARK: - isConcurrentRequestsError

    func test_isConcurrentRequestsError_concurrentRequestsを含むエラーを検知する() {
        let error = FakeError(description: "concurrentRequests(Context(debugDescription: \"...\"))")

        XCTAssertTrue(FoundationModelTextGenerator.isConcurrentRequestsError(error))
    }

    func test_isConcurrentRequestsError_関係ないエラーはfalse() {
        XCTAssertFalse(FoundationModelTextGenerator.isConcurrentRequestsError(URLError(.badServerResponse)))
    }

    // MARK: - isRateLimitedError

    func test_isRateLimitedError_rateLimitedを含むエラーを検知する() {
        let error = FakeError(description: "rateLimited(RateLimited(resetDate: nil))")

        XCTAssertTrue(FoundationModelTextGenerator.isRateLimitedError(error))
    }

    func test_isRateLimitedError_関係ないエラーはfalse() {
        XCTAssertFalse(FoundationModelTextGenerator.isRateLimitedError(URLError(.badServerResponse)))
    }

    // MARK: - RemoteAITextGenerator

    func test_remoteAITextGenerator_OpenAIResponsesAPIを呼びoutputTextを返す() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "gpt-5.5")
            XCTAssertEqual(json["instructions"] as? String, "inst")
            XCTAssertEqual(json["input"] as? String, "prompt")
            return (200, Data(#"{"output_text":"ok"}"#.utf8))
        }

        let generator = RemoteAITextGenerator(provider: .openAI, apiKey: "sk-test", session: .mock())

        let result = try await generator.generate(instructions: "inst", prompt: "prompt")

        XCTAssertEqual(result, "ok")
    }

    func test_remoteAITextGenerator_GeminiInteractionsAPIを呼びoutputTextを返す() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/interactions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "gemini-3.5-flash")
            XCTAssertTrue((json["input"] as? String)?.contains("inst") == true)
            XCTAssertTrue((json["input"] as? String)?.contains("prompt") == true)
            return (200, Data(#"{"output_text":"ok"}"#.utf8))
        }

        let generator = RemoteAITextGenerator(provider: .gemini, apiKey: "gemini-key", session: .mock())

        let result = try await generator.generate(instructions: "inst", prompt: "prompt")

        XCTAssertEqual(result, "ok")
    }

    func test_remoteAITextGenerator_ClaudeMessagesAPIを呼びtextContentを返す() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "claude-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-5")
            XCTAssertEqual(json["system"] as? String, "inst")
            return (200, Data(#"{"content":[{"type":"text","text":"ok"}]}"#.utf8))
        }

        let generator = RemoteAITextGenerator(provider: .claude, apiKey: "claude-key", session: .mock())

        let result = try await generator.generate(instructions: "inst", prompt: "prompt")

        XCTAssertEqual(result, "ok")
    }
}
