package com.mtkg.gogai.store

/// 配列の要素を並び替え、id 配列を永続化した上で、成功時のみ並び替え後の配列を返す共通ヘルパー。
/// GroupStore.reorderGroups / FeedStore.reorderFeeds / StockStore.reorderCategories が
/// 同じ「move → id 配列送信 → 書き戻し」を個別実装していたのをまとめる（iOS ReorderHelper の移植）。
/// persist が失敗した場合は例外を投げるだけで返り値を返さないため、呼び出し側が
/// 返り値をそのまま StateFlow へ代入する形にすれば、ローカル状態はサーバーへの送信に
/// 成功するまで変更されない（失敗時のコミット漏れがない）。
suspend fun <T> reorderAndPersist(
    items: List<T>,
    from: Int,
    to: Int,
    idOf: (T) -> Int,
    persist: suspend (List<Int>) -> Unit,
): List<T> {
    val reordered = moveItem(items, from, to)
    persist(reordered.map(idOf))
    return reordered
}

/// SwiftUI の `Array.move(fromOffsets:toOffset:)`（単一要素移動）相当の実装。
/// destination（to）は移動前の配列に対するインデックスで、末尾へ移動する場合は items.size を渡す。
private fun <T> moveItem(items: List<T>, from: Int, to: Int): List<T> {
    if (from == to || from !in items.indices) return items
    val mutable = items.toMutableList()
    val item = mutable.removeAt(from)
    val insertIndex = (if (to > from) to - 1 else to).coerceIn(0, mutable.size)
    mutable.add(insertIndex, item)
    return mutable
}
