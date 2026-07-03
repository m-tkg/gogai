import type Database from 'better-sqlite3'
import { StockCategoriesService } from './stock-categories.js'

export interface Stock {
  id: number
  url: string
  title: string | null
  source: string
  category_id: number
  summary: string | null
  stocked_at: string
  created_at: string
}

export interface StockView extends Stock {
  category_name: string
  has_translation: boolean
}

export interface CreateStockInput {
  url: string
  title?: string
  source?: string
  category?: string
}

export interface UpdateStockInput {
  title: string
  category: string
}

export interface StockTranslation {
  segments: string
  translated_at: string
}

interface StockViewRow extends Stock {
  category_name: string
  has_translation: number
}

export class StocksService {
  private categories: StockCategoriesService

  constructor(private db: Database.Database) {
    this.categories = new StockCategoriesService(db)
  }

  private toView(row: StockViewRow): StockView {
    return { ...row, has_translation: Boolean(row.has_translation) }
  }

  private findRowById(id: number): StockViewRow | undefined {
    return this.db
      .prepare(
        `SELECT s.*, c.name as category_name,
                EXISTS(SELECT 1 FROM stock_translations t WHERE t.stock_id = s.id) as has_translation
         FROM stocks s
         JOIN stock_categories c ON c.id = s.category_id
         WHERE s.id = ?`
      )
      .get(id) as StockViewRow | undefined
  }

  private findByUrl(url: string): Stock | undefined {
    return this.db.prepare('SELECT * FROM stocks WHERE url = ?').get(url) as Stock | undefined
  }

  findAll(categoryId?: number): StockView[] {
    const query = `
      SELECT s.*, c.name as category_name,
             EXISTS(SELECT 1 FROM stock_translations t WHERE t.stock_id = s.id) as has_translation
      FROM stocks s
      JOIN stock_categories c ON c.id = s.category_id
      ${categoryId !== undefined ? 'WHERE s.category_id = ?' : ''}
      ORDER BY s.stocked_at DESC, s.id DESC
    `
    const rows = (
      categoryId !== undefined ? this.db.prepare(query).all(categoryId) : this.db.prepare(query).all()
    ) as StockViewRow[]
    return rows.map((row) => this.toView(row))
  }

  findById(id: number): StockView | null {
    const row = this.findRowById(id)
    return row ? this.toView(row) : null
  }

  // url が既に存在する場合は何もせず既存ストックを返す（no-op）。created で新規作成かを判別できる
  create(input: CreateStockInput): { stock: StockView; created: boolean } {
    const existing = this.findByUrl(input.url)
    if (existing) {
      return { stock: this.toView(this.findRowById(existing.id) as StockViewRow), created: false }
    }

    const categoryName = input.category?.trim() || input.source?.trim() || '未分類'
    const category = this.categories.getOrCreate(categoryName)

    const created = this.db
      .prepare(
        `INSERT INTO stocks (url, title, source, category_id)
         VALUES (?, ?, ?, ?)
         RETURNING id`
      )
      .get(input.url, input.title ?? null, input.source ?? '', category.id) as { id: number }

    return { stock: this.toView(this.findRowById(created.id) as StockViewRow), created: true }
  }

  update(id: number, input: UpdateStockInput): StockView | null {
    const stock = this.db.prepare('SELECT * FROM stocks WHERE id = ?').get(id) as Stock | undefined
    if (!stock) return null

    const newCategory = this.categories.getOrCreate(input.category)
    this.db
      .prepare('UPDATE stocks SET title = ?, category_id = ? WHERE id = ?')
      .run(input.title, newCategory.id, id)

    if (stock.category_id !== newCategory.id) {
      this.categories.removeIfEmpty(stock.category_id)
    }

    return this.toView(this.findRowById(id) as StockViewRow)
  }

  remove(id: number): void {
    const stock = this.db.prepare('SELECT * FROM stocks WHERE id = ?').get(id) as Stock | undefined
    if (!stock) return
    this.db.prepare('DELETE FROM stocks WHERE id = ?').run(id)
    this.categories.removeIfEmpty(stock.category_id)
  }

  // 更新できたら true、対象が存在しなければ false
  setSummary(id: number, summary: string): boolean {
    const result = this.db.prepare('UPDATE stocks SET summary = ? WHERE id = ?').run(summary, id)
    return result.changes > 0
  }

  getTranslation(id: number): StockTranslation | null {
    return (
      (this.db
        .prepare('SELECT segments, translated_at FROM stock_translations WHERE stock_id = ?')
        .get(id) as StockTranslation) ?? null
    )
  }

  upsertTranslation(id: number, segments: string): void {
    this.db
      .prepare(
        `INSERT INTO stock_translations (stock_id, segments, translated_at)
         VALUES (?, ?, datetime('now'))
         ON CONFLICT(stock_id) DO UPDATE SET segments = excluded.segments, translated_at = excluded.translated_at`
      )
      .run(id, segments)
  }

  deleteTranslation(id: number): void {
    this.db.prepare('DELETE FROM stock_translations WHERE stock_id = ?').run(id)
  }
}
