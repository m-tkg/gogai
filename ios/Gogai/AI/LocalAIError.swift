import Foundation

/// ローカル AI(Foundation Models)関連の処理で共通して発生するエラー。
/// LocalArticleAI/StockSummarizer/FMPageTranslator/StockStore が個別に持っていた
/// 4つの類似 enum(LocalArticleAIError/StockSummarizerError/FMPageTranslatorError/
/// StockSummaryGenerationError)を統一する。
enum LocalAIError: Error, LocalizedError, Equatable {
    /// タイトル・本文のどちらも空で AI に渡すテキストがない
    case emptyContent
    /// モデル応答から期待した形式の結果を取り出せなかった(例: 翻訳の id タグ)
    case parseFailed
    /// この端末でローカル AI(Foundation Models)を利用できない
    case aiUnavailable
    /// URL が不正で処理できない
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "本文が空のため処理できません"
        case .parseFailed:
            return "AI の応答を解析できませんでした"
        case .aiUnavailable:
            return "この端末ではローカル AI を利用できません(iOS 27 以上と Apple Intelligence の有効化が必要です)"
        case .invalidURL:
            return "URL が不正です"
        }
    }
}
