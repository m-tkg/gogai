import Foundation

/// ストックした記事を4セクション構成(何についての記事か/何の目的で書かれたか/
/// 筆者が一番伝えたいこと/20行以内の要約)で日本語要約する。
/// オンデバイスモデルのトークン制限を超える本文は、チャンク分割した中間要約を
/// 経由する map-reduce で最終要約を生成する。
struct StockSummarizer: Sendable {
    /// 最終段プロンプトに渡す本文の上限文字数。
    /// LocalArticleAI.maxPromptLength と同じ制約(オンデバイスモデルの入出力合計 4096 トークン)から
    /// 来る値のため、値を重複定義せず参照する。
    static let maxPromptLength = LocalArticleAI.maxPromptLength
    /// 外部 AI はオンデバイスよりコンテキストが大きく、API rate limit の方が問題になりやすい。
    /// map-reduce で複数リクエストに分割せず、1回の要約に寄せるための上限。
    static let remoteMaxPromptLength = 20_000
    /// 中間要約 1 チャンクあたりの文字数。
    /// maxPromptLength より小さい値を意図的に使う: 中間要約プロンプトには
    /// 「チャンク本文 + 指示文」が乗るため、最終段より余裕を持たせる必要がある。
    static let chunkSize = 2800
    /// 中間要約チャンクの上限数(超過分は切り捨てる)
    static let maxChunks = 8
    /// 「要約」セクションの最大行数
    static let summaryLineLimit = 20
    /// セクション個別生成で空が返ったときにリトライする最大回数。
    /// オンデバイスモデルは同じプロンプトでも中身が空になることがあるため、
    /// 非空になるまで(この回数まで)再試行する。
    static let maxGenerationRetries = 2

    /// セクション個別生成でも中身が得られなかったときに埋めるプレースホルダ。
    /// これを入れることで4見出しすべてが非空になり StockSummary.parse() が必ず成功する
    /// (=表示側が固定見出しレイアウト・見出しの色付けを常に行える)。
    static let sectionPlaceholder = "（生成できませんでした）"

    private let generator: any TextGenerating

    init(generator: any TextGenerating) {
        self.generator = generator
    }

    /// 記事 URL から本文を取得してサマリーを生成する
    func summarize(url: URL, title: String?, session: URLSession = .shared) async throws -> String {
        let text = try await ArticleContentFetcher.fetchPlainText(from: url, session: session)
        return try await summarize(title: title, text: text)
    }

    /// 取得済みの本文からサマリーを生成する(テスト用に URL 取得と分離)
    func summarize(title: String?, text: String) async throws -> String {
        let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = ArticleContentFetcher.stripHTML(text)
        guard !cleanTitle.isEmpty || !cleanText.isEmpty else { throw LocalAIError.emptyContent }

        let sourceText: String
        if generator is RemoteAITextGenerator {
            sourceText = String(cleanText.prefix(Self.remoteMaxPromptLength))
        } else {
            sourceText = cleanText.count <= Self.maxPromptLength
                ? cleanText
                : try await condense(text: cleanText)
        }

        let prompt = [cleanTitle, sourceText].filter { !$0.isEmpty }.joined(separator: "\n\n")

        // 通常経路: 1回の生成で4セクションをまとめて作らせる。parse できればそのまま採用。
        let combined = Self.enforceSummaryLineLimit(try await generator.generate(instructions: Self.finalInstructions, prompt: prompt))
        if StockSummary.parse(combined) != nil {
            return combined
        }

        // 外部 AI では rate limit を避けるため、セクションごとの追加生成は行わない。
        // 1回目の出力を「要約」本文として採用し、固定見出しはこちら側で補う。
        if generator is RemoteAITextGenerator {
            return Self.assembleSections(
                topic: Self.sectionPlaceholder,
                purpose: Self.sectionPlaceholder,
                mainMessage: Self.sectionPlaceholder,
                summaryLines: Array(Self.sectionLines(combined).prefix(Self.summaryLineLimit))
            )
        }

        // フォールバック: オンデバイスモデルが1回では一部セクションしか埋めないことがあるため、
        // セクションごとに個別生成し、見出しはこちら側で固定して組み立てる。
        // これにより各項目が確実に埋まり、parse も必ず成功する(=見出しは常に色付き表示)。
        return try await summarizeBySection(prompt: prompt)
    }

    /// 4セクションを1項目ずつ個別生成し、固定見出しで組み立てる。
    private func summarizeBySection(prompt: String) async throws -> String {
        let topic = try await generateSectionLines(instructions: Self.topicInstruction, prompt: prompt)
        let purpose = try await generateSectionLines(instructions: Self.purposeInstruction, prompt: prompt)
        let mainMessage = try await generateSectionLines(instructions: Self.mainMessageInstruction, prompt: prompt)
        let summary = try await generateSectionLines(instructions: Self.summaryInstruction, prompt: prompt)
        return Self.assembleSections(
            topic: topic.joined(separator: "\n"),
            purpose: purpose.joined(separator: "\n"),
            mainMessage: mainMessage.joined(separator: "\n"),
            summaryLines: Array(summary.prefix(Self.summaryLineLimit))
        )
    }

    /// 1セクション分を生成し、見出し行を除去した本文行の配列を返す。
    /// 空で返ったときは maxGenerationRetries まで再生成する。
    private func generateSectionLines(instructions: String, prompt: String) async throws -> [String] {
        var lines = Self.sectionLines(try await generator.generate(instructions: instructions, prompt: prompt))
        var attempt = 0
        while lines.isEmpty, attempt < Self.maxGenerationRetries {
            attempt += 1
            lines = Self.sectionLines(try await generator.generate(instructions: instructions, prompt: prompt))
        }
        return lines
    }

    /// モデル出力から見出し行(先頭が #)と空行を除いた本文行の配列を返す。
    /// モデルがセクション本文に見出しをエコーバックしても最終出力の構造を壊さないため。
    static func sectionLines(_ text: String) -> [String] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 各セクション本文を固定見出しに差し込んで最終テキストを組み立てる。
    /// 空セクションは sectionPlaceholder で埋め、4見出しすべてが非空になるようにする
    /// (StockSummary.parse() が必ず成功する)。
    static func assembleSections(topic: String, purpose: String, mainMessage: String, summaryLines: [String]) -> String {
        func filled(_ body: String) -> String { body.isEmpty ? sectionPlaceholder : body }
        let summaryBody = summaryLines.isEmpty ? sectionPlaceholder : summaryLines.joined(separator: "\n")
        return """
        ## 何についての記事か
        \(filled(topic))

        ## 何の目的で書かれたか
        \(filled(purpose))

        ## 筆者が一番伝えたいこと
        \(filled(mainMessage))

        ## 要約(20行以内)
        \(summaryBody)
        """
    }

    /// 本文をチャンク分割し、各チャンクを日本語箇条書きに中間要約してから連結する
    private func condense(text: String) async throws -> String {
        let chunks = Self.chunk(text, size: Self.chunkSize, maxChunks: Self.maxChunks)
        var intermediates: [String] = []
        for chunk in chunks {
            let result = try await generator.generate(instructions: Self.intermediateInstructions, prompt: chunk)
            intermediates.append(result)
        }
        return String(intermediates.joined(separator: "\n").prefix(Self.maxPromptLength))
    }

    /// テキストを size 文字ごとに分割する(maxChunks を超える分は切り捨て)
    static func chunk(_ text: String, size: Int, maxChunks: Int) -> [String] {
        var chunks: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty, chunks.count < maxChunks {
            let end = remaining.index(remaining.startIndex, offsetBy: size, limitedBy: remaining.endIndex) ?? remaining.endIndex
            chunks.append(String(remaining[remaining.startIndex..<end]))
            remaining = remaining[end...]
        }
        return chunks
    }

    /// 「## 要約」セクションの本文を summaryLineLimit 行までに機械的に切り詰める。
    /// プロンプト指示だけでは 20 行を超える出力がありうるためハードに保証する。
    static func enforceSummaryLineLimit(_ text: String, limit: Int = summaryLineLimit) -> String {
        guard let headingRange = text.range(of: "## 要約") else { return text }
        let head = String(text[..<headingRange.lowerBound])
        let tail = text[headingRange.lowerBound...]
        var lines = tail.components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }
        let heading = lines.removeFirst()
        let limitedBody = lines.prefix(limit)
        return head + ([heading] + limitedBody).joined(separator: "\n")
    }

    static let finalInstructions = """
    あなたは記事要約アシスタントです。与えられた記事を必ず日本語で要約してください。
    出力は以下の見出しのみで構成し、見出し以外の文章(前置き・後書き)を追加しないでください。

    ## 何についての記事か
    ## 何の目的で書かれたか
    ## 筆者が一番伝えたいこと
    ## 要約(20行以内)
    """

    static let intermediateInstructions = "あなたは記事要約アシスタントです。与えられた記事の一部を、日本語の要点箇条書きに変換してください。"

    // MARK: - セクション個別生成用の指示(フォールバック時)

    static let topicInstruction = "あなたは記事要約アシスタントです。与えられた記事が「何についての記事か」を、日本語で1〜2文で説明してください。見出しや箇条書き記号は付けず、説明文だけを出力してください。"
    static let purposeInstruction = "あなたは記事要約アシスタントです。与えられた記事が「何の目的で書かれたか」を、日本語で1〜2文で説明してください。見出しや箇条書き記号は付けず、説明文だけを出力してください。"
    static let mainMessageInstruction = "あなたは記事要約アシスタントです。与えられた記事で「筆者が一番伝えたいこと」を、日本語で1〜2文で説明してください。見出しや箇条書き記号は付けず、説明文だけを出力してください。"
    static let summaryInstruction = "あなたは記事要約アシスタントです。与えられた記事を日本語で要約してください。要点を1行ずつ、20行以内で出力してください。見出しや前置きは付けないでください。"
}
