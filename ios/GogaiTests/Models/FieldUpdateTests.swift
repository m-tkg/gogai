import XCTest
@testable import Gogai

final class FieldUpdateTests: XCTestCase {
    func test_keepは既存値を保持する() {
        let update: FieldUpdate<String> = .keep
        XCTAssertEqual(update.apply(to: "existing"), "existing")
        XCTAssertNil(update.apply(to: nil))
    }

    func test_clearはnilにする() {
        let update: FieldUpdate<String> = .clear
        XCTAssertNil(update.apply(to: "existing"))
    }

    func test_setは指定した値に差し替える() {
        let update: FieldUpdate<String> = .set("new")
        XCTAssertEqual(update.apply(to: "existing"), "new")
        XCTAssertEqual(update.apply(to: nil), "new")
    }
}
