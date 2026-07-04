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
    /// concurrentRequests を受けて短い待機の後に再試行する最大回数
    static let maxConcurrentRetries = 2
    /// concurrentRequests 検知時の待機時間(要約キューが翻訳優先で中断した際、
    /// オンデバイスモデル側の処理がまだ終わっていない場合の猶予)
    static let concurrentRetryDelay: Duration = .milliseconds(300)
    /// rateLimited を受けて再試行する最大回数
    static let maxRateLimitRetries = 2
    /// rateLimited 検知時の待機時間(試行ごとに指数的に伸ばす)
    static let rateLimitRetryDelays: [Duration] = [.seconds(1), .seconds(2)]

    func generate(instructions: String, prompt: String) async throws -> String {
        try await generate(
            instructions: instructions, prompt: prompt,
            remainingContextRetries: Self.maxContextRetries,
            remainingConcurrentRetries: Self.maxConcurrentRetries,
            remainingRateLimitRetries: Self.maxRateLimitRetries
        )
    }

    private func generate(
        instructions: String, prompt: String,
        remainingContextRetries: Int, remainingConcurrentRetries: Int, remainingRateLimitRetries: Int
    ) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            if remainingConcurrentRetries > 0, Self.isConcurrentRequestsError(error) {
                try await Task.sleep(for: Self.concurrentRetryDelay)
                return try await generate(
                    instructions: instructions, prompt: prompt,
                    remainingContextRetries: remainingContextRetries,
                    remainingConcurrentRetries: remainingConcurrentRetries - 1,
                    remainingRateLimitRetries: remainingRateLimitRetries
                )
            }
            if remainingRateLimitRetries > 0, Self.isRateLimitedError(error) {
                let attempt = Self.maxRateLimitRetries - remainingRateLimitRetries
                try await Task.sleep(for: Self.rateLimitRetryDelays[attempt])
                return try await generate(
                    instructions: instructions, prompt: prompt,
                    remainingContextRetries: remainingContextRetries,
                    remainingConcurrentRetries: remainingConcurrentRetries,
                    remainingRateLimitRetries: remainingRateLimitRetries - 1
                )
            }
            guard remainingContextRetries > 0, let shrunkPrompt = Self.shrinkPromptIfContextExceeded(prompt, error: error) else {
                throw error
            }
            return try await generate(
                instructions: instructions, prompt: shrunkPrompt,
                remainingContextRetries: remainingContextRetries - 1,
                remainingConcurrentRetries: remainingConcurrentRetries,
                remainingRateLimitRetries: remainingRateLimitRetries
            )
        }
    }

    /// LanguageModelSession.Error.concurrentRequests(オンデバイスモデルは同時に1リクエストしか
    /// 処理できない)を検知する。型ではなくキーワードで判定する理由は shrinkPromptIfContextExceeded と同じ。
    static func isConcurrentRequestsError(_ error: Error) -> Bool {
        String(describing: error).lowercased().contains("concurrentrequests")
    }

    /// LanguageModelSession.Error.rateLimited / LanguageModelError.rateLimited(オンデバイスモデルの
    /// 単位時間あたりのリクエスト数制限)を検知する。型ではなくキーワードで判定する理由は
    /// shrinkPromptIfContextExceeded と同じ。
    static func isRateLimitedError(_ error: Error) -> Bool {
        String(describing: error).lowercased().contains("ratelimited")
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
