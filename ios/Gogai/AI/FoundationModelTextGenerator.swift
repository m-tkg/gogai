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
    func generate(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
