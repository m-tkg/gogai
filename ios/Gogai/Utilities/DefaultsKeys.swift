import Foundation

/// UserDefaults のキーを一元管理する（散在ハードコードと衝突を防ぐ）
enum DefaultsKeys {
    /// 旧・未読のみフィルター（Bool）。articleFilter への移行元としてのみ読む
    static let unreadOnly = "unreadOnly"
    static let articleFilter = "articleFilter"
    static let sortOrder = "sortOrder"
    static let serverURL = "serverURL"
    static let resolvedServerURL = "resolvedServerURL"
    static let translationEngine = "translationEngine"
    static let aiProvider = "aiProvider"
    static let stockSortAscending = "stockSortAscending"
    static let stockSummaryQueue = "stockSummaryQueue"
    static let stockSummaryErrors = "stockSummaryErrors"
}
