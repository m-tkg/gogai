import XCTest
@testable import Gogai

private struct Item: Identifiable, Equatable {
    let id: Int
}

private struct ReorderTestError: Error {}

final class ReorderHelperTests: XCTestCase {
    @MainActor
    func test_指定した範囲を並び替えてid配列をpersistに渡す() async throws {
        let items = [Item(id: 1), Item(id: 2), Item(id: 3)]
        var persistedIds: [Int]?

        let result = try await reorderAndPersist(items, from: IndexSet(integer: 2), to: 0) { ids in
            persistedIds = ids
        }

        XCTAssertEqual(result.map(\.id), [3, 1, 2])
        XCTAssertEqual(persistedIds, [3, 1, 2])
    }

    @MainActor
    func test_persistが失敗したら配列を返さずthrowする() async {
        let items = [Item(id: 1), Item(id: 2)]

        do {
            _ = try await reorderAndPersist(items, from: IndexSet(integer: 0), to: 2) { _ in
                throw ReorderTestError()
            }
            XCTFail("エラーが throw されるはず")
        } catch is ReorderTestError {
            // 期待通り
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }
}
