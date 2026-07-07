import XCTest
@testable import Gogai

final class SHA256HexDigestTests: XCTestCase {
    func test_空文字列の既知のSHA256値を返す() {
        XCTAssertEqual(
            "".sha256HexDigest,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func test_abcの既知のSHA256値を返す() {
        XCTAssertEqual(
            "abc".sha256HexDigest,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func test_異なる入力は異なるダイジェストを返す() {
        XCTAssertNotEqual("a".sha256HexDigest, "b".sha256HexDigest)
    }
}
