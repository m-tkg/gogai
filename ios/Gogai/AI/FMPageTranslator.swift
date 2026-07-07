import Foundation

/// Foundation Model でウェブページのテキストノードを翻訳する。
/// ノード単体を独立して翻訳すると文脈が失われるため、文書順の連続ノードを
/// 1バッチにまとめ、id タグ付きで一括翻訳することで文脈を保つ。
/// UI・WebKit・キャッシュに依存しない純粋なロジックのみを持つ(テスト容易性のため)。
struct FMPageTranslator: Sendable {
    /// 1バッチに含める原文の合計文字数の目安。
    /// 日本語訳は原文より膨らむため、入出力合計 4096 トークンに余裕を持たせて小さめに取る。
    static let batchCharBudget = 1800

    struct Segment: Equatable, Sendable {
        let index: Int
        let text: String
    }

    private let generator: any TextGenerating

    init(generator: any TextGenerating) {
        self.generator = generator
    }

    /// `texts`(文書順の全ノード)のうち `indicesToTranslate` を日本語へ翻訳する。
    /// バッチ翻訳が失敗、または応答に id が欠落したノードは単体で個別リトライする。
    /// 個別リトライにも失敗したノードは戻り値に含まれない(呼び出し側は原文のまま表示する)。
    func translate(texts: [String], indicesToTranslate: [Int], pageTitle: String) async -> [Int: String] {
        guard !indicesToTranslate.isEmpty else { return [:] }
        let segments = indicesToTranslate.map { Segment(index: $0, text: texts[$0]) }

        var results: [Int: String] = [:]
        for batch in Self.makeBatches(segments, charBudget: Self.batchCharBudget) {
            guard let first = batch.first else { continue }
            // バッチ先頭ノードの直前ノードを、翻訳対象にも出力対象にも含めない文脈として渡す
            let contextText = first.index > 0 ? texts[first.index - 1] : nil
            if let translated = try? await translateBatch(batch, contextText: contextText, pageTitle: pageTitle) {
                for (index, text) in translated { results[index] = text }
            }
            for segment in batch where results[segment.index] == nil {
                if let text = try? await translateSingle(segment, pageTitle: pageTitle) {
                    results[segment.index] = text
                }
            }
        }
        return results
    }

    // MARK: - バッチ生成

    /// 連続するセグメントを合計文字数が charBudget を超えない範囲でバッチにまとめる
    static func makeBatches(_ segments: [Segment], charBudget: Int) -> [[Segment]] {
        var batches: [[Segment]] = []
        var current: [Segment] = []
        var currentLength = 0
        for segment in segments {
            if !current.isEmpty && currentLength + segment.text.count > charBudget {
                batches.append(current)
                current = []
                currentLength = 0
            }
            current.append(segment)
            currentLength += segment.text.count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    // MARK: - プロンプト・応答パース

    private func translateBatch(_ batch: [Segment], contextText: String?, pageTitle: String) async throws -> [Int: String] {
        let response = try await generator.generate(
            instructions: Self.instructions(pageTitle: pageTitle),
            prompt: Self.buildPrompt(batch: batch, contextText: contextText)
        )
        return Self.parseResponse(response)
    }

    private func translateSingle(_ segment: Segment, pageTitle: String) async throws -> String {
        let response = try await generator.generate(
            instructions: Self.instructions(pageTitle: pageTitle),
            prompt: Self.buildPrompt(batch: [segment], contextText: nil)
        )
        guard let text = Self.parseResponse(response)[segment.index] else {
            throw LocalAIError.parseFailed
        }
        return text
    }

    static func buildPrompt(batch: [Segment], contextText: String?) -> String {
        var lines: [String] = []
        if let contextText, !contextText.isEmpty {
            lines.append("⟦ctx⟧\(contextText)")
        }
        for segment in batch {
            lines.append("⟦\(segment.index)⟧\(segment.text)")
        }
        return lines.joined(separator: "\n")
    }

    static func instructions(pageTitle: String) -> String {
        """
        あなたは翻訳者です。ウェブページ「\(pageTitle)」の断片を、文脈を保ちながら自然な日本語に翻訳してください。
        各行は「⟦id⟧原文」の形式です。同じ id を使って「⟦id⟧訳文」の行だけを、原文と同じ順序で出力してください。
        「⟦ctx⟧」で始まる行は文脈把握のための参考情報です。翻訳せず、出力にも含めないでください。
        id の追加・削除・順序の変更はしないでください。
        """
    }

    /// 「⟦id⟧訳文」形式の応答を id → 訳文 の辞書にパースする。
    /// 「⟦ctx⟧」など数字でない id は自然に無視される。
    static func parseResponse(_ response: String) -> [Int: String] {
        guard let regex = try? NSRegularExpression(pattern: "⟦(\\d+)⟧") else { return [:] }
        let ns = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: ns.length))
        var result: [Int: String] = [:]
        for (i, match) in matches.enumerated() {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: response),
                  let id = Int(response[idRange]) else { continue }
            let contentStart = match.range.location + match.range.length
            let contentEnd = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            guard contentEnd >= contentStart else { continue }
            let content = ns.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[id] = content
        }
        return result
    }
}
