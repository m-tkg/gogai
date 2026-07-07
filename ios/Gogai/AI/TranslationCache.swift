import Foundation

/// 翻訳結果のローカルキャッシュ（1週間で失効）。
/// キーは「翻訳エンジン + 原文」のハッシュで、同じ原文でもエンジンが違えば別エントリ。
/// ページ内翻訳ではテキストノード単位、基盤モデル翻訳では記事本文単位で使う。
@MainActor
final class TranslationCache {
    static let shared = TranslationCache()

    /// キャッシュの有効期間（1週間）
    static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    private struct Entry: Codable {
        let target: String
        let cachedAt: Date
    }

    private let fileURL: URL
    private var entries: [String: Entry]

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gogai")) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("translationCache.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = loaded
        } else {
            entries = [:]
        }
    }

    /// 原文に対するキャッシュ済みの訳文を返す（失効していれば nil）
    func target(for source: String, engine: TranslationEngine, now: Date = Date()) -> String? {
        guard let entry = entries[Self.key(source: source, engine: engine)] else { return nil }
        guard now.timeIntervalSince(entry.cachedAt) < Self.timeToLive else { return nil }
        return entry.target
    }

    /// 訳文をキャッシュに登録する（persist を呼ぶまでメモリのみ）
    func store(source: String, target: String, engine: TranslationEngine, now: Date = Date()) {
        entries[Self.key(source: source, engine: engine)] = Entry(target: target, cachedAt: now)
    }

    /// 失効エントリを破棄してディスクへ保存する
    func persist(now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.cachedAt) < Self.timeToLive }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func key(source: String, engine: TranslationEngine) -> String {
        "\(engine.rawValue)\u{0}\(source)".sha256HexDigest
    }
}
