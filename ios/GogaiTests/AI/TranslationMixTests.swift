import XCTest
@testable import Gogai

final class TranslationMixTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.translationMixRatio)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.translationMixRatio)
        super.tearDown()
    }

    private func translatedIndices(count: Int, ratio: Int, offset: Int = 0) -> [Int] {
        (0..<count).filter { TranslationMix.isTranslated(index: $0, ratio: ratio, offset: offset) }
    }

    func test_100パーセントなら全文が訳文() {
        XCTAssertEqual(translatedIndices(count: 5, ratio: 100), [0, 1, 2, 3, 4])
    }

    func test_0パーセントなら訳文なし() {
        XCTAssertEqual(translatedIndices(count: 5, ratio: 0), [])
    }

    func test_割合どおりの文数が均等に散らばる() {
        XCTAssertEqual(translatedIndices(count: 10, ratio: 40).count, 4)
        XCTAssertEqual(translatedIndices(count: 10, ratio: 50), [1, 3, 5, 7, 9])
        XCTAssertEqual(translatedIndices(count: 100, ratio: 30).count, 30)
    }

    func test_オフセットを変えると別の文が選ばれる() {
        let a = translatedIndices(count: 10, ratio: 50, offset: 0)
        let b = translatedIndices(count: 10, ratio: 50, offset: 1)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, b.count)
    }

    func test_範囲外の割合はクランプされる() {
        XCTAssertEqual(TranslationMix.clamp(-10), 0)
        XCTAssertEqual(TranslationMix.clamp(150), 100)
        XCTAssertEqual(translatedIndices(count: 3, ratio: 150), [0, 1, 2])
    }

    func test_savedRatio_未設定なら既定値() {
        XCTAssertEqual(TranslationMix.savedRatio, TranslationMix.defaultRatio)
    }

    func test_savedRatio_保存と読み出し() {
        TranslationMix.savedRatio = 70
        XCTAssertEqual(TranslationMix.savedRatio, 70)
        TranslationMix.savedRatio = 999
        XCTAssertEqual(TranslationMix.savedRatio, 100, "範囲外はクランプして保存する")
    }
}
