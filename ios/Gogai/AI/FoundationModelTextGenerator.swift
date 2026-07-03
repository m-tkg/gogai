import Foundation
import FoundationModels

/// ローカル AI 機能の入口。
/// ユーザー方針により iOS/iPadOS 27 以上でのみ機能を有効化する
/// （API 自体は iOS 26 から存在するが、プロバイダー差し替え可能な
///  LanguageModel プロトコル世代である 27 を最低ラインとする）。
enum LocalAI {
    /// iOS/iPadOS 27 以上かつオンデバイスモデルが利用可能なときだけ true
    static var isAvailable: Bool {
        guard #available(iOS 27.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// 利用可能なら既定のオンデバイス実装で LocalArticleAI を作る
    static func makeArticleAI() -> LocalArticleAI? {
        guard let generator = makeGenerator() else { return nil }
        return LocalArticleAI(generator: generator)
    }

    /// 利用可能なら既定のオンデバイス TextGenerating 実装を返す(ストック要約など LocalArticleAI 以外の用途で共用)
    static func makeGenerator() -> (any TextGenerating)? {
        guard #available(iOS 27.0, *), isAvailable else { return nil }
        return FoundationModelTextGenerator()
    }
}

/// Apple のオンデバイス基盤モデル（Foundation Models framework）による実装
@available(iOS 26.0, *)
struct FoundationModelTextGenerator: TextGenerating {
    /// contextSizeExceeded を受けてプロンプトを縮小し再試行する最大回数
    static let maxContextRetries = 2

    func generate(instructions: String, prompt: String) async throws -> String {
        try await generate(instructions: instructions, prompt: prompt, remainingRetries: Self.maxContextRetries)
    }

    private func generate(instructions: String, prompt: String, remainingRetries: Int) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            guard remainingRetries > 0, let shrunkPrompt = Self.shrinkPromptIfContextExceeded(prompt, error: error) else {
                throw error
            }
            return try await generate(instructions: instructions, prompt: shrunkPrompt, remainingRetries: remainingRetries - 1)
        }
    }

    /// コンテキスト長超過エラーを受けてプロンプトを縮める。
    /// 対応するエラー型(LanguageModelError.contextSizeExceeded 等)はビルドに使う
    /// Xcode/SDK バージョンによって存在しないことがある(型で判定すると環境依存でビルドが壊れる)ため、
    /// エラーの説明文言に含まれるキーワードで判定する。
    /// それ以外のエラーや、これ以上縮められない場合は nil を返す(= リトライしない)。
    static func shrinkPromptIfContextExceeded(_ prompt: String, error: Error) -> String? {
        let description = String(describing: error).lowercased()
        guard description.contains("context"),
              description.contains("exceed") || description.contains("window") else {
            return nil
        }
        let targetLength = max(200, prompt.count / 2)
        guard targetLength < prompt.count else { return nil }
        return String(prompt.prefix(targetLength))
    }
}
