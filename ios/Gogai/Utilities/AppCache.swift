import Foundation

/// アプリのローカルキャッシュを管理するクラス
/// 記事・フィード・グループをCachesディレクトリにJSONファイルとして保存する
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
