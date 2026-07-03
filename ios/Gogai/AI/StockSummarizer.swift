import Foundation

enum StockSummarizerError: Error, Equatable {
    /// 記事本文が空でサマリー対象がない
    case emptyContent
}

/// ストックした記事を4セクション構成(何についての記事か/何の目的で書かれたか/
/// 筆者が一番伝えたいこと/20行以内の要約)で日本語要約する。
/// オンデバイスモデルのトークン制限を超える本文は、チャンク分割した中間要約を
/// 経由する map-reduce で最終要約を生成する。
struct StockSummarizer: Sendable {
    /// 最終段プロンプトに渡す本文の上限文字数(LocalArticleAI.maxPromptLength と同じ考え方)
    static let maxPromptLength = 3000
    /// 中間要約 1 チャンクあたりの文字数
    static let chunkSize = 2800
    /// 中間要約チャンクの上限数(超過分は切り捨てる)
    static let maxChunks = 8
    /// 「要約」セクションの最大行数
    static let summaryLineLimit = 20

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
        let cleanText = LocalArticleAI.stripHTML(text)
        guard !cleanTitle.isEmpty || !cleanText.isEmpty else { throw StockSummarizerError.emptyContent }

        let sourceText = cleanText.count <= Self.maxPromptLength
            ? cleanText
            : try await condense(text: cleanText)

        let prompt = [cleanTitle, sourceText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let raw = try await generator.generate(instructions: Self.finalInstructions, prompt: prompt)
        return Self.enforceSummaryLineLimit(raw)
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
}
