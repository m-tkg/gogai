import Foundation

/// 配列の要素を並び替え、id 配列を永続化した上で、成功時のみ並び替え後の配列を返す共通ヘルパー。
/// GroupStore.reorderGroups/FeedStore.reorderFeeds/StockStore.reorderCategories が
/// 同じ「move → id 配列送信 → 書き戻し」を個別実装していたのをまとめる。
/// persist が失敗した場合は throw するだけで返り値を返さないため、呼び出し側が
/// 返り値を @Published プロパティへ代入する形にすれば、ローカル状態は
/// サーバーへの送信に成功するまで変更されない(失敗時のコミット漏れがない)。
@MainActor
func reorderAndPersist<T: Identifiable>(
    _ items: [T],
    from source: IndexSet,
    to destination: Int,
    persist: @MainActor ([T.ID]) async throws -> Void
) async throws -> [T] {
    var reordered = items
    reordered.move(fromOffsets: source, toOffset: destination)
    try await persist(reordered.map(\.id))
    return reordered
}
