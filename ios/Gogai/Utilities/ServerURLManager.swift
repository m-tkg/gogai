import Foundation

@MainActor
final class ServerURLManager: ObservableObject {
    private let userDefaultsKey = DefaultsKeys.serverURL
    private let resolvedURLKey = DefaultsKeys.resolvedServerURL
    private let session: URLSession
    private let failureDebounceInterval: TimeInterval
    private var lastReportedFailureAt: Date?

    /// UserDefaults に保存された生の URL（Gist URL の場合もある）
    @Published private(set) var serverURL: URL?
    /// 実際に API クライアントが使う解決済み URL
    @Published private(set) var resolvedURL: URL?
    @Published private(set) var isResolving = false

    var isConfigured: Bool { serverURL != nil }

    private static func isGistURL(_ url: URL) -> Bool {
        url.host == "gist.github.com"
    }

    init(session: URLSession = .shared, failureDebounceInterval: TimeInterval = 30) {
        self.session = session
        self.failureDebounceInterval = failureDebounceInterval
        Self.migrateFromStandardDefaultsIfNeeded()
        if let urlString = AppGroup.defaults.string(forKey: userDefaultsKey),
           let url = URL(string: urlString) {
            serverURL = url
            // Why: 起動時に Gist API 解決を待たず前回のトンネル URL で即座に
            // configureStores() を走らせるためキャッシュを復元する。非 Gist URL は
            // resolve() が即座に自身をセットするためキャッシュ不要。
            if Self.isGistURL(url) {
                resolvedURL = loadCachedResolvedURL()
            }
        }
    }

    /// 旧 UserDefaults.standard に保存された値を App Group の suite へ 1 回だけ移す。
    /// シェア拡張追加前のインストールからのアップグレードでも resolvedServerURL が引き継がれるようにする。
    private static func migrateFromStandardDefaultsIfNeeded() {
        let suite = AppGroup.defaults
        guard suite.string(forKey: DefaultsKeys.serverURL) == nil else { return }
        guard let legacyServerURL = UserDefaults.standard.string(forKey: DefaultsKeys.serverURL) else { return }
        suite.set(legacyServerURL, forKey: DefaultsKeys.serverURL)
        if let legacyResolvedURL = UserDefaults.standard.string(forKey: DefaultsKeys.resolvedServerURL) {
            suite.set(legacyResolvedURL, forKey: DefaultsKeys.resolvedServerURL)
        }
    }

    func setServerURL(_ url: URL) {
        AppGroup.defaults.set(url.absoluteString, forKey: userDefaultsKey)
        AppGroup.defaults.removeObject(forKey: resolvedURLKey)
        serverURL = url
        resolvedURL = nil
    }

    func clearServerURL() {
        AppGroup.defaults.removeObject(forKey: userDefaultsKey)
        AppGroup.defaults.removeObject(forKey: resolvedURLKey)
        serverURL = nil
        resolvedURL = nil
    }

    /// APIClient の接続失敗通知を受けて再解決する（キャッシュ URL が失効しているかもしれない想定）。
    /// デバウンスで連続呼び出しを抑制する。
    /// - 成功時: resolvedURL が新 URL に更新され、onChange 経由で自動再構成される。
    /// - 失敗時: resolvedURL はそのまま。キャッシュも既存値を維持し、次回起動で再試行できる。
    func reportFailure() async {
        if let last = lastReportedFailureAt,
           Date().timeIntervalSince(last) < failureDebounceInterval {
            return
        }
        lastReportedFailureAt = Date()
        await resolve()
    }

    /// Gist URL なら API 経由でコンテンツを取得して実 URL を解決する
    func resolve() async {
        guard let url = serverURL else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            let resolved = try await Self.resolveURL(url, session: session)
            resolvedURL = resolved
            if Self.isGistURL(url) {
                cacheResolvedURL(resolved)
            }
        } catch {
            // Why: 失敗時は既存の resolvedURL を維持する。init 時に復元した
            // キャッシュ済み URL があればそれで API を叩き続けられるし、
            // resolvedURL が元々 nil なら nil のまま（setServerURL 直後の失敗に相当）。
            // gist.github.com URL が resolvedURL に入ることはない（Self.resolveURL は
            // 成功時は必ず非 Gist URL を返し、失敗時は throw するため）。
        }
    }

    /// gist.github.com URL を GitHub Gist API 経由で解決する。それ以外はそのまま返す。
    static func resolveURL(_ url: URL, session: URLSession = .shared) async throws -> URL {
        guard isGistURL(url) else { return url }
        let gistId = url.lastPathComponent
        let apiURL = URL(string: "https://api.github.com/gists/\(gistId)")!
        let (data, _) = try await session.data(from: apiURL)
        struct GistFile: Decodable { let content: String }
        struct GistResponse: Decodable { let files: [String: GistFile] }
        let gist = try JSONDecoder().decode(GistResponse.self, from: data)
        guard let content = gist.files.values.first?.content
                                .trimmingCharacters(in: .whitespacesAndNewlines),
              let resolved = URL(string: content) else {
            throw URLError(.cannotParseResponse)
        }
        return resolved
    }

    // MARK: - Resolved URL cache

    private func loadCachedResolvedURL() -> URL? {
        guard let cached = AppGroup.defaults.string(forKey: resolvedURLKey) else { return nil }
        return URL(string: cached)
    }

    private func cacheResolvedURL(_ url: URL) {
        AppGroup.defaults.set(url.absoluteString, forKey: resolvedURLKey)
    }
}
