@testable import Gogai

/// TextGenerating のテスト用モック。応答キュー・ハンドラ・受信 instructions/prompt 記録・
/// エラー注入・呼び出し回数のすべてを持つ統合版。用途に応じて必要なプロパティだけ使えばよい。
///
/// - `result`: 固定の単発応答(`responses` が空のときのフォールバック)
/// - `responses`: 呼び出しごとに順番に返すキュー(空になったら `result` を返す)
/// - `responseHandler`: instructions/prompt から動的に応答を組み立てたい場合に使う(設定時は最優先)
final class MockTextGenerator: TextGenerating, @unchecked Sendable {
    var result = "生成結果"
    var responses: [String] = []
    var responseHandler: ((String, String) -> String)?
    var error: Error?
    private(set) var callCount = 0
    private(set) var receivedInstructions: [String] = []
    private(set) var receivedPrompts: [String] = []
    var lastInstructions: String? { receivedInstructions.last }
    var lastPrompt: String? { receivedPrompts.last }

    func generate(instructions: String, prompt: String) async throws -> String {
        callCount += 1
        receivedInstructions.append(instructions)
        receivedPrompts.append(prompt)
        if let error { throw error }
        if let responseHandler { return responseHandler(instructions, prompt) }
        if !responses.isEmpty { return responses.removeFirst() }
        return result
    }
}
