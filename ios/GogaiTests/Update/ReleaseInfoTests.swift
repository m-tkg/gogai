import XCTest
@testable import Gogai

final class VersionComparatorTests: XCTestCase {
    func test_isNewer_vプレフィックス付きの新しいタグを検出() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.1", than: "1.0"))
        XCTAssertTrue(VersionComparator.isNewer(tag: "v2.0", than: "1.9"))
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.0.1", than: "1.0"))
    }

    func test_isNewer_同一または古いタグはfalse() {
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.0", than: "1.0"))
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.0", than: "1.1"))
        XCTAssertFalse(VersionComparator.isNewer(tag: "1.0", than: "1.0.0"))
    }

    func test_isNewer_数値として比較する() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.10", than: "1.9"))
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.9", than: "1.10"))
    }

    func test_isNewer_非数値サフィックスは先頭の数字のみ採用() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.2-beta", than: "1.1"))
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.0-beta", than: "1.0"))
    }
}

final class ReleaseInfoTests: XCTestCase {
    private let json = """
    {
      "tag_name": "v1.2.0",
      "html_url": "https://github.com/m-tkg/gogai/releases/tag/v1.2.0",
      "assets": [
        {"name": "Gogai.zip", "browser_download_url": "https://example.com/Gogai.zip"},
        {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"}
      ]
    }
    """

    func test_decode_GitHubレスポンスをデコードする() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(release.tagName, "v1.2.0")
        XCTAssertEqual(release.assets.count, 2)
    }

    func test_zipAssetURL_zipアセットのURLを取得する() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(release.zipAssetURL, URL(string: "https://example.com/Gogai.zip"))
    }

    func test_zipAssetURL_assets欠落でもデコードできzipAssetURLはnil() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(#"{"tag_name":"v1.0.0","html_url":"x"}"#.utf8))
        XCTAssertTrue(release.assets.isEmpty)
        XCTAssertNil(release.zipAssetURL)
    }
}
