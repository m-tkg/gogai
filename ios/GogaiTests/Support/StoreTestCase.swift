import XCTest
@testable import Gogai

/// Store 系テストの共通セットアップ・ティアダウン。
/// `.mock()` セッションを使った固定 baseURL の APIClient を用意し、tearDown で MockURLProtocol をリセットする。
/// Store 固有の初期化(configure・追加の UserDefaults リセットなど)はサブクラスの setUp/tearDown で行い、
/// 必ず super を呼ぶこと。
class StoreTestCase: XCTestCase {
    private(set) var client: APIClient!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "http://localhost:3040")!, session: .mock())
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }
}
