import XCTest
@testable import Gogai

@MainActor
final class ServerURLManagerTests: XCTestCase {
    let gistURL = URL(string: "https://gist.github.com/m-tkg/abc123")!

    override func setUp() {
        super.setUp()
        AppGroup.defaults.removeObject(forKey: "serverURL")
        AppGroup.defaults.removeObject(forKey: "resolvedServerURL")
        UserDefaults.standard.removeObject(forKey: "serverURL")
        UserDefaults.standard.removeObject(forKey: "resolvedServerURL")
    }

    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: "serverURL")
        AppGroup.defaults.removeObject(forKey: "resolvedServerURL")
        UserDefaults.standard.removeObject(forKey: "serverURL")
        UserDefaults.standard.removeObject(forKey: "resolvedServerURL")
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // Why: シェア拡張追加前のインストールでは serverURL が UserDefaults.standard に
    // 保存されている。App Group 移行後も再設定不要で引き継げることを保証する。
    func test_init_standardDefaultsからAppGroupへ1回だけ移行する() {
        UserDefaults.standard.set("http://localhost:3040", forKey: "serverURL")
        UserDefaults.standard.set("https://legacy.trycloudflare.com", forKey: "resolvedServerURL")

        _ = ServerURLManager(session: .mock())

        XCTAssertEqual(AppGroup.defaults.string(forKey: "serverURL"), "http://localhost:3040")
        XCTAssertEqual(AppGroup.defaults.string(forKey: "resolvedServerURL"), "https://legacy.trycloudflare.com")
    }

    func test_init_AppGroupに既に値があれば移行しない() {
        AppGroup.defaults.set("http://new.example.com", forKey: "serverURL")
        UserDefaults.standard.set("http://old.example.com", forKey: "serverURL")

        _ = ServerURLManager(session: .mock())

        XCTAssertEqual(AppGroup.defaults.string(forKey: "serverURL"), "http://new.example.com")
    }

    func test_resolve_gistAPISuccess_setsResolvedURL() async {
        let tunnel = "https://abcd.trycloudflare.com"
        MockURLProtocol.requestHandler = { _ in
            let body = "{\"files\":{\"url.txt\":{\"content\":\"\(tunnel)\"}}}"
            return (200, Data(body.utf8))
        }
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(gistURL)

        await manager.resolve()

        XCTAssertEqual(manager.resolvedURL?.absoluteString, tunnel)
    }

    // Why: Gist API が 404 やネットワーク失敗を返した時に APIClient が
    // gist.github.com に対して /api/* を投げるのを防ぐ。失敗時は resolvedURL を
    // nil のまま保持してユーザーが再試行できるようにする。
    func test_resolve_gistAPIFailure_keepsResolvedURLNil() async {
        MockURLProtocol.requestHandler = { _ in
            (404, Data("{\"message\":\"Not Found\"}".utf8))
        }
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(gistURL)

        await manager.resolve()

        XCTAssertNil(manager.resolvedURL,
                     "Gist 解決失敗時に resolvedURL に gist.github.com URL を入れてはいけない")
    }

    func test_resolve_gistAPIInvalidJSON_keepsResolvedURLNil() async {
        MockURLProtocol.requestHandler = { _ in (200, Data("not json".utf8)) }
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(gistURL)

        await manager.resolve()

        XCTAssertNil(manager.resolvedURL)
    }

    // Why: URL(string:) は "trycloudflare.com" のような scheme/host を欠いた文字列でも
    // nil を返さず解析してしまう(相対パスとして扱われる)。そのまま resolvedURL に入れると
    // URLSession が実際にリクエストを送る段階で初めて URLError.badURL として失敗し、
    // どこが壊れているか分かりにくいエラーになる。resolve() の時点で検知して弾く。
    func test_resolve_gistContentがscheme無しの不正なURLならresolvedURLをnilのままにする() async {
        MockURLProtocol.requestHandler = { _ in
            let body = "{\"files\":{\"url.txt\":{\"content\":\"trycloudflare.com\"}}}"
            return (200, Data(body.utf8))
        }
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(gistURL)

        await manager.resolve()

        XCTAssertNil(manager.resolvedURL, "scheme/host を欠いた URL を resolvedURL に入れてはいけない")
    }

    func test_resolve_nonGistURL_setsResolvedURLDirectly() async {
        let direct = URL(string: "http://localhost:3040")!
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(direct)

        await manager.resolve()

        XCTAssertEqual(manager.resolvedURL, direct)
    }

    // Why: 起動時に Gist API を待たず、前回解決したトンネル URL を即座に使うため。
    // これにより configureStores() が起動直後に走り、初期表示が高速化する。
    func test_init_restoresCachedResolvedURL_whenGistURLSaved() {
        let tunnel = "https://cached.trycloudflare.com"
        AppGroup.defaults.set(gistURL.absoluteString, forKey: "serverURL")
        AppGroup.defaults.set(tunnel, forKey: "resolvedServerURL")

        let manager = ServerURLManager(session: .mock())

        XCTAssertEqual(manager.resolvedURL?.absoluteString, tunnel)
    }

    func test_resolve_success_cachesResolvedURL() async {
        let tunnel = "https://newtunnel.trycloudflare.com"
        MockURLProtocol.requestHandler = { _ in
            let body = "{\"files\":{\"url.txt\":{\"content\":\"\(tunnel)\"}}}"
            return (200, Data(body.utf8))
        }
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(gistURL)

        await manager.resolve()

        XCTAssertEqual(
            AppGroup.defaults.string(forKey: "resolvedServerURL"),
            tunnel
        )
    }

    func test_setServerURL_clearsCachedResolvedURL() {
        AppGroup.defaults.set("https://old.trycloudflare.com", forKey: "resolvedServerURL")
        let manager = ServerURLManager(session: .mock())

        manager.setServerURL(gistURL)

        XCTAssertNil(AppGroup.defaults.string(forKey: "resolvedServerURL"))
    }

    func test_clearServerURL_clearsCachedResolvedURL() {
        AppGroup.defaults.set(gistURL.absoluteString, forKey: "serverURL")
        AppGroup.defaults.set("https://old.trycloudflare.com", forKey: "resolvedServerURL")
        let manager = ServerURLManager(session: .mock())

        manager.clearServerURL()

        XCTAssertNil(AppGroup.defaults.string(forKey: "resolvedServerURL"))
    }

    // Why: 非 Gist URL は resolve() が即座にそのままセットするため、キャッシュを使う必要がない。
    // 古いキャッシュが残っていても init 時点の resolvedURL は nil のままであるべき。
    func test_init_ignoresCachedResolvedURL_forNonGistServerURL() {
        let direct = "http://localhost:3040"
        AppGroup.defaults.set(direct, forKey: "serverURL")
        AppGroup.defaults.set("https://stale.trycloudflare.com", forKey: "resolvedServerURL")

        let manager = ServerURLManager(session: .mock())

        XCTAssertNil(manager.resolvedURL)
    }

    // Why: APIClient の失敗通知を受けて再解決することで、トンネル URL 失効からの自動回復を実現する。
    func test_reportFailure_triggersResolve() async {
        let newTunnel = "https://recovered.trycloudflare.com"
        MockURLProtocol.requestHandler = { _ in
            let body = "{\"files\":{\"url.txt\":{\"content\":\"\(newTunnel)\"}}}"
            return (200, Data(body.utf8))
        }
        let manager = ServerURLManager(session: .mock(), failureDebounceInterval: 0)
        manager.setServerURL(gistURL)

        await manager.reportFailure()

        XCTAssertEqual(manager.resolvedURL?.absoluteString, newTunnel)
    }

    // Why: 起動時に 3 本の並列 API が全て失敗すると onNetworkFailure が 3 回呼ばれるため、
    // デバウンスがないと Gist API を無駄に 3 回叩く。
    func test_reportFailure_debouncesWithinInterval() async {
        let counter = ResolveCounter()
        MockURLProtocol.requestHandler = { _ in
            counter.increment()
            let body = "{\"files\":{\"url.txt\":{\"content\":\"https://t.trycloudflare.com\"}}}"
            return (200, Data(body.utf8))
        }
        let manager = ServerURLManager(session: .mock(), failureDebounceInterval: 60)
        manager.setServerURL(gistURL)

        await manager.reportFailure()
        await manager.reportFailure()
        await manager.reportFailure()

        XCTAssertEqual(counter.value, 1, "デバウンス期間内の連続呼び出しでは Gist API を 1 回しか叩かないこと")
    }

    func test_reportFailure_allowsRetryAfterInterval() async {
        let counter = ResolveCounter()
        MockURLProtocol.requestHandler = { _ in
            counter.increment()
            let body = "{\"files\":{\"url.txt\":{\"content\":\"https://t.trycloudflare.com\"}}}"
            return (200, Data(body.utf8))
        }
        let manager = ServerURLManager(session: .mock(), failureDebounceInterval: 0)
        manager.setServerURL(gistURL)

        await manager.reportFailure()
        await manager.reportFailure()

        XCTAssertEqual(counter.value, 2, "デバウンス間隔 0 なら毎回 resolve が走ること")
    }
}

/// Mock ハンドラから呼ばれるため @Sendable 対応のカウンタ
private final class ResolveCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}
