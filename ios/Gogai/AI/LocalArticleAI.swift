import Foundation

/// ローカル AI へのテキスト生成依頼を抽象化するプロトコル。
/// 現在はオンデバイスの Foundation Models 実装のみだが、iOS 27 の LanguageModel
/// プロトコルによるクラウドプロバイダー（Claude / Gemini 等）への差し替えを見据えた seam。
protocol TextGenerating: Sendable {
    func generate(instructions: String, prompt: String) async throws -> String
}

/// 日本語翻訳に使うエンジンの選択（設定画面で切り替え、UserDefaults で永続化）
enum TranslationEngine: String, CaseIterable, Identifiable {
    /// オンデバイス基盤モデル（Foundation Models framework）に翻訳させる
    case foundationModel
    /// システムの翻訳専用モデル（Translation framework）を使う
    case translationFramework

    var id: String { rawValue }

    var label: String {
        switch self {
        case .foundationModel: return "ローカル AI（基盤モデル）"
        case .translationFramework: return "システム翻訳"
        }
    }

    static var current: TranslationEngine {
        get {
            let saved = UserDefaults.standard.string(forKey: DefaultsKeys.translationEngine) ?? ""
            return TranslationEngine(rawValue: saved) ?? .foundationModel
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKeys.translationEngine)
        }
    }
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
        guard !prompt.isEmpty else { throw LocalAIError.emptyContent }
        return try await generator.generate(
            instructions: "あなたは記事要約アシスタントです。与えられた記事を日本語で3〜5文に要約してください。要約の本文のみを出力してください。",
            prompt: prompt
        )
    }

    /// 記事を日本語に翻訳する
    func translateToJapanese(title: String?, content: String?) async throws -> String {
        let prompt = Self.preparePrompt(title: title, content: content)
        guard !prompt.isEmpty else { throw LocalAIError.emptyContent }
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
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“",
            "&hellip;": "…", "&mldr;": "…", "&mdash;": "—", "&ndash;": "–",
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = decodeNumericEntities(text)
        return text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 数値文字参照(&#NNN; / &#xHHHH;)をデコードする。アイコンフォント用の私用領域
    /// (Private Use Area)コードポイントはテキストとして意味を持たないため空文字にする。
    private static func decodeNumericEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#x?[0-9a-fA-F]+;", options: .caseInsensitive) else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let token = ns.substring(with: match.range)
            if let scalar = decodeEntityScalar(token), !isPrivateUse(scalar) {
                result += String(Character(scalar))
            }
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    private static func decodeEntityScalar(_ token: String) -> Unicode.Scalar? {
        let inner = token.dropFirst(2).dropLast() // "&#" 接頭辞と ";" 接尾辞を除去
        let isHex = inner.hasPrefix("x") || inner.hasPrefix("X")
        let digits = isHex ? inner.dropFirst() : inner[...]
        guard let value = UInt32(digits, radix: isHex ? 16 : 10) else { return nil }
        return Unicode.Scalar(value)
    }

    private static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool {
        (0xE000...0xF8FF).contains(scalar.value)
            || (0xF0000...0xFFFFD).contains(scalar.value)
            || (0x100000...0x10FFFD).contains(scalar.value)
    }
}
