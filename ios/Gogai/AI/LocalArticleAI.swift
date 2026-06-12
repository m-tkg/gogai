import Foundation

/// ローカル AI へのテキスト生成依頼を抽象化するプロトコル。
/// 現在はオンデバイスの Foundation Models 実装のみだが、iOS 27 の LanguageModel
/// プロトコルによるクラウドプロバイダー（Claude / Gemini 等）への差し替えを見据えた seam。
protocol TextGenerating: Sendable {
    func generate(instructions: String, prompt: String) async throws -> String
}

enum LocalArticleAIError: Error, Equatable {
    /// タイトル・本文のどちらも空で AI に渡すテキストがない
    case emptyContent
}

/// 記事の日本語要約・日本語翻訳をローカル AI で行うサービス。
/// 結果はサーバーに保存しない（オンデバイス生成は無料・即時のため都度生成する）。
struct LocalArticleAI: Sendable {
    /// オンデバイスモデルは入出力合計 4096 トークンの制限があるため、
    /// 出力分の余裕を残して入力テキストをこの文字数で切り詰める
    static let maxPromptLength = 3000

    private let generator: any TextGenerating

    init(generator: any TextGenerating) {
        self.generator = generator
    }

    /// 記事を日本語で要約する
    func summarize(title: String?, content: String?) async throws -> String {
        let prompt = Self.preparePrompt(title: title, content: content)
        guard !prompt.isEmpty else { throw LocalArticleAIError.emptyContent }
        return try await generator.generate(
            instructions: "あなたは記事要約アシスタントです。与えられた記事を日本語で3〜5文に要約してください。要約の本文のみを出力してください。",
            prompt: prompt
        )
    }

    /// 記事を日本語に翻訳する
    func translateToJapanese(title: String?, content: String?) async throws -> String {
        let prompt = Self.preparePrompt(title: title, content: content)
        guard !prompt.isEmpty else { throw LocalArticleAIError.emptyContent }
        return try await generator.generate(
            instructions: "あなたは翻訳アシスタントです。与えられた記事を自然な日本語に翻訳してください。訳文のみを出力してください。",
            prompt: prompt
        )
    }

    /// タイトルと本文（HTML）を AI に渡すプレーンテキストに整形する。
    /// HTML タグ・主要エンティティを除去し、コンテキスト上限に収まるよう切り詰める。
    static func preparePrompt(title: String?, content: String?) -> String {
        let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = stripHTML(content ?? "")
        let combined = [cleanTitle, cleanBody]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return String(combined.prefix(maxPromptLength))
    }

    static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
