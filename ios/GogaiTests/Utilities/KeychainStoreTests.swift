import XCTest
@testable import Gogai

final class KeychainStoreTests: XCTestCase {
    private let key = "KeychainStoreTests.testKey"

    override func tearDown() {
        KeychainStore.set(nil, forKey: key)
        super.tearDown()
    }

    func test_setAndGet_roundTrips() {
        KeychainStore.set("s3cret", forKey: key)

        XCTAssertEqual(KeychainStore.get(forKey: key), "s3cret")
    }

    func test_get_returnsNil_whenNotSet() {
        XCTAssertNil(KeychainStore.get(forKey: key))
    }

    func test_set_overwritesExistingValue() {
        KeychainStore.set("first", forKey: key)
        KeychainStore.set("second", forKey: key)

        XCTAssertEqual(KeychainStore.get(forKey: key), "second")
    }

    func test_setNil_deletesValue() {
        KeychainStore.set("s3cret", forKey: key)
        KeychainStore.set(nil, forKey: key)

        XCTAssertNil(KeychainStore.get(forKey: key))
    }
}
