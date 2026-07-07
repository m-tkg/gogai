import type Database from 'better-sqlite3'

/// ids の順序どおりに table.display_order を 0 始まりで振り直す。
/// table は呼び出し側が固定文字列で渡す前提(ユーザー入力を直接渡さない)。
export function reorderByDisplayOrder(db: Database.Database, table: string, ids: number[]): void {
  if (ids.length === 0) return
  const stmt = db.prepare(`UPDATE ${table} SET display_order = ? WHERE id = ?`)
  const updateMany = db.transaction((orderedIds: number[]) => {
    orderedIds.forEach((id, index) => {
      stmt.run(index, id)
    })
  })
  updateMany(ids)
}
