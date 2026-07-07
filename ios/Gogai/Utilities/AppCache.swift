import Foundation

/// アプリのローカルキャッシュを管理するクラス
/// 記事・フィード・グループをCachesディレクトリにJSONファイルとして保存する
///
/// `@unchecked Sendable` の根拠: 内部状態は初期化後に変更されない `directory: URL` のみ。
/// 将来可変プロパティを追加する場合は `NSLock` 等によるスレッド安全性の確保が必要。
final class AppCache: @unchecked Sendable {
    static let shared = AppCache()

    private let directory: URL

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gogai")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Articles

    func saveAllArticles(_ articles: [Article]) {
        save(articles, to: "allArticles.json")
    }

    func loadAllArticles() -> [Article] {
        load([Article].self, from: "allArticles.json") ?? []
    }

    // MARK: - FeedCounts

    func saveFeedCounts(_ counts: [FeedCount]) {
        save(counts, to: "feedCounts.json")
    }

    func loadFeedCounts() -> [FeedCount] {
        load([FeedCount].self, from: "feedCounts.json") ?? []
    }

    // MARK: - Feeds

    func saveFeeds(_ feeds: [Feed]) {
        save(feeds, to: "feeds.json")
    }

    func loadFeeds() -> [Feed] {
        load([Feed].self, from: "feeds.json") ?? []
    }

    // MARK: - Groups

    func saveGroups(_ groups: [Group]) {
        save(groups, to: "groups.json")
    }

    func loadGroups() -> [Group] {
        load([Group].self, from: "groups.json") ?? []
    }

    // MARK: - Stocks

    func saveStocks(_ stocks: [Stock]) {
        save(stocks, to: "stocks.json")
    }

    func loadStocks() -> [Stock] {
        load([Stock].self, from: "stocks.json") ?? []
    }

    func saveStockCategories(_ categories: [StockCategory]) {
        save(categories, to: "stockCategories.json")
    }

    func loadStockCategories() -> [StockCategory] {
        load([StockCategory].self, from: "stockCategories.json") ?? []
    }

    // MARK: - Size

    var totalSize: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        return enumerator.compactMap { $0 as? URL }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0) { $0 + Int64($1) }
    }

    // MARK: - Clear

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = directory.appendingPathComponent(filename)
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
