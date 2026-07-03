import Foundation

/// UserDefaults のキーを一元管理する（散在ハードコードと衝突を防ぐ）
enum DefaultsKeys {
    static let unreadOnly = "unreadOnly"
    static let favoriteOnly = "favoriteOnly"
    static let sortOrder = "sortOrder"
    static let serverURL = "serverURL"
    static let resolvedServerURL = "resolvedServerURL"
    static let translationEngine = "translationEngine"
    static let stockSortAscending = "stockSortAscending"
}
