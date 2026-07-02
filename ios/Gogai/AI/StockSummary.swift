import Foundation

/// StockSummarizer が生成した固定見出しテキストをセクションごとに分割した表示用モデル。
/// サーバーには見出し付きプレーンテキストのまま保存し、表示側でこのパーサを通す。
struct StockSummary: Equatable, Sendable {
    let topic: String
    let purpose: String
    let mainMessage: String
    let summaryLines: [String]

    /// 見出しが1つでも欠けていれば nil を返す(呼び出し側は生テキスト表示にフォールバックする)
    static func parse(_ text: String) -> StockSummary? {
        let sections = splitSections(text)
        guard let topic = sections["何についての記事か"],
              let purpose = sections["何の目的で書かれたか"],
              let mainMessage = sections["筆者が一番伝えたいこと"],
              let summaryBody = sections["要約"] else { return nil }

        let lines = summaryBody
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return StockSummary(topic: topic, purpose: purpose, mainMessage: mainMessage, summaryLines: lines)
    }

    /// "## 見出し" 区切りでセクション本文を集める。「要約(20行以内)」のような
    /// 補足付き見出しも "要約" を含んでいれば "要約" キーとして扱う。
    private static func splitSections(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        var currentBody: [String] = []

        func flush() {
            guard let key = currentKey else { return }
            result[key] = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                flush()
                let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                currentKey = normalizedKey(heading)
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        flush()
        return result
    }

    private static func normalizedKey(_ heading: String) -> String {
        heading.contains("要約") ? "要約" : heading
    }
}
