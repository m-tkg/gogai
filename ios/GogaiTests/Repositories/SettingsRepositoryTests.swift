import XCTest
@testable import Gogai

final class SettingsRepositoryTests: XCTestCase {
    var client: APIClient!
    var repository: SettingsRepository!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
        repository = SettingsRepository(client: client)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        KeychainStore.set(nil, forKey: KeychainStore.adminSecretKey)
        super.tearDown()
    }

    func test_checkUpdate_sendsAdminSecretHeader_whenSetInKeychain() async throws {
        KeychainStore.set("s3cret", forKey: KeychainStore.adminSecretKey)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Admin-Secret"), "s3cret")
            let body = """
            {"local":"a","remote":"a","hasUpdate":false}
            """
            return (200, Data(body.utf8))
        }

        _ = try await repository.checkUpdate()
    }

    func test_checkUpdate_omitsAdminSecretHeader_whenNotSetInKeychain() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Admin-Secret"))
            let body = """
            {"local":"a","remote":"a","hasUpdate":false}
            """
            return (200, Data(body.utf8))
        }

        _ = try await repository.checkUpdate()
    }

    func test_restart_sendsAdminSecretHeader_whenSetInKeychain() async throws {
        KeychainStore.set("s3cret", forKey: KeychainStore.adminSecretKey)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Admin-Secret"), "s3cret")
            return (200, Data("{\"output\":\"ok\"}".utf8))
        }

        _ = try await repository.restart()
    }
}
