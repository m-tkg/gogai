import Foundation

@MainActor
final class ServerURLManager: ObservableObject {
    private let userDefaultsKey = "serverURL"
    private let session: URLSession

    /// UserDefaults に保存された生の URL（Gist URL の場合もある）
    @Published private(set) var serverURL: URL?
    /// 実際に API クライアントが使う解決済み URL
    @Published private(set) var resolvedURL: URL?
    @Published private(set) var isResolving = false

    var isConfigured: Bool { serverURL != nil }

    init(session: URLSession = .shared) {
        self.session = session
        if let urlString = UserDefaults.standard.string(forKey: userDefaultsKey),
           let url = URL(string: urlString) {
            serverURL = url
        }
    }

    func setServerURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: userDefaultsKey)
        serverURL = url
        resolvedURL = nil
    }

    func clearServerURL() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        serverURL = nil
        resolvedURL = nil
    }

    /// Gist URL なら API 経由でコンテンツを取得して実 URL を解決する
    func resolve() async {
        guard let url = serverURL else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            resolvedURL = try await Self.resolveURL(url, session: session)
        } catch {
            resolvedURL = url  // 解決失敗時はそのまま使用
        }
    }

    /// gist.github.com URL を GitHub Gist API 経由で解決する。それ以外はそのまま返す。
    static func resolveURL(_ url: URL, session: URLSession = .shared) async throws -> URL {
        guard url.host == "gist.github.com" else { return url }
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
}
