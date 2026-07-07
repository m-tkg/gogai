import type Database from 'better-sqlite3'

/// table(必要なら whereClause で絞り込んだ範囲)の末尾に追加する場合の display_order を返す。
/// table・whereClause は呼び出し側が固定文字列で渡す前提(ユーザー入力を直接渡さない)。
export function nextDisplayOrder(
  db: Database.Database,
  table: string,
  whereClause?: string,
  params: unknown[] = []
): number {
  const sql = `SELECT COALESCE(MAX(display_order), -1) as max_order FROM ${table}${whereClause ? ` WHERE ${whereClause}` : ''}`
  const maxOrder = (db.prepare(sql).get(...params) as { max_order: number }).max_order
  return maxOrder + 1
}
