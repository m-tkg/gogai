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

    func saveAllArticles(_ articles: [Article]) {
        // stub
    }

    func loadAllArticles() -> [Article] {
        // stub
        return []
    }

    func saveFeeds(_ feeds: [Feed]) {
        // stub
    }

    func loadFeeds() -> [Feed] {
        // stub
        return []
    }

    func saveGroups(_ groups: [Group]) {
        // stub
    }

    func loadGroups() -> [Group] {
        // stub
        return []
    }

    func clearAll() {
        // stub
    }
}
