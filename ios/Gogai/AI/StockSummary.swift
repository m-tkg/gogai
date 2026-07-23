import Foundation

/// StockSummarizer が生成した固定見出しテキストをセクションごとに分割した表示用モデル。
/// サーバーには見出し付きプレーンテキストのまま保存し、表示側でこのパーサを通す。
struct StockSummary: Equatable, Sendable {
    let topic: String
    let purpose: String
    let mainMessage: String
    let summaryLines: [String]
    /// 「この記事から得られる学び」セクション。既存保存済みの4セクション形式には
    /// このセクションがないため、見出し自体がない・本文が空の場合は nil にする
    /// (表示側は nil なら学び見出しごと非表示にし、旧データの構造化表示を維持する)。
    let learningLines: [String]?

    /// 4セクション(何についての記事か/何の目的で書かれたか/筆者が一番伝えたいこと/要約)が
    /// 1つでも欠けている、または中身が空(オンデバイスモデルが見出しだけ出力した場合)なら
    /// nil を返す(呼び出し側は生テキスト表示にフォールバックする)。
    /// 学びセクションは optional 扱いのため、この判定には含めない。
    static func parse(_ text: String) -> StockSummary? {
        let sections = splitSections(text)
        guard let topic = sections["何についての記事か"], !topic.isEmpty,
              let purpose = sections["何の目的で書かれたか"], !purpose.isEmpty,
              let mainMessage = sections["筆者が一番伝えたいこと"], !mainMessage.isEmpty,
              let summaryBody = sections["要約"], !summaryBody.isEmpty else { return nil }

        let learningBody = sections["学び"]
        let learningLines = learningBody.map(bodyLines)
        return StockSummary(
            topic: topic,
            purpose: purpose,
            mainMessage: mainMessage,
            summaryLines: bodyLines(summaryBody),
            learningLines: (learningLines?.isEmpty ?? true) ? nil : learningLines
        )
    }

    private static func bodyLines(_ body: String) -> [String] {
        body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
        if heading.contains("要約") { return "要約" }
        if heading.contains("学び") { return "学び" }
        return heading
    }
}
