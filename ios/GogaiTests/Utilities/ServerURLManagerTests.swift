import XCTest
@testable import Gogai

@MainActor
final class ServerURLManagerTests: XCTestCase {
    let gistURL = URL(string: "https://gist.github.com/m-tkg/abc123")!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "serverURL")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "serverURL")
        MockURLProtocol.requestHandler = nil
        super.tearDown()
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

    func test_resolve_nonGistURL_setsResolvedURLDirectly() async {
        let direct = URL(string: "http://localhost:3040")!
        let manager = ServerURLManager(session: .mock())
        manager.setServerURL(direct)

        await manager.resolve()

        XCTAssertEqual(manager.resolvedURL, direct)
    }
}
