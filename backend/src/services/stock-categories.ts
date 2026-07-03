import type Database from 'better-sqlite3'

export interface StockCategory {
  id: number
  name: string
  display_order: number
  created_at: string
}

export interface StockCategoryWithCount extends StockCategory {
  stock_count: number
}

export class StockCategoriesService {
  constructor(private db: Database.Database) {}

  findAllWithCount(): StockCategoryWithCount[] {
    return this.db
      .prepare(
        `SELECT c.*, COUNT(s.id) as stock_count
         FROM stock_categories c
         LEFT JOIN stocks s ON s.category_id = c.id
         GROUP BY c.id
         ORDER BY c.display_order ASC, c.id ASC`
      )
      .all() as StockCategoryWithCount[]
  }

  findById(id: number): StockCategory | null {
    return (this.db.prepare('SELECT * FROM stock_categories WHERE id = ?').get(id) as StockCategory) ?? null
  }

  // 名前(trim 済み)一致で既存カテゴリを再利用し、なければ末尾に新規作成する
  getOrCreate(name: string): StockCategory {
    const trimmed = name.trim()
    const existing = this.db
      .prepare('SELECT * FROM stock_categories WHERE name = ?')
      .get(trimmed) as StockCategory | undefined
    if (existing) return existing

    const maxOrder = (
      this.db.prepare('SELECT COALESCE(MAX(display_order), -1) as max_order FROM stock_categories').get() as {
        max_order: number
      }
    ).max_order
    return this.db
      .prepare('INSERT INTO stock_categories (name, display_order) VALUES (?, ?) RETURNING *')
      .get(trimmed, maxOrder + 1) as StockCategory
  }

  // カテゴリに紐づくストックが 0 件なら削除する
  removeIfEmpty(id: number): void {
    const count = (
      this.db.prepare('SELECT COUNT(*) as count FROM stocks WHERE category_id = ?').get(id) as { count: number }
    ).count
    if (count === 0) {
      this.db.prepare('DELETE FROM stock_categories WHERE id = ?').run(id)
    }
  }

  reorder(ids: number[]): void {
    if (ids.length === 0) return
    const stmt = this.db.prepare('UPDATE stock_categories SET display_order = ? WHERE id = ?')
    const updateMany = this.db.transaction((orderedIds: number[]) => {
      orderedIds.forEach((id, index) => {
        stmt.run(index, id)
      })
    })
    updateMany(ids)
  }
}
