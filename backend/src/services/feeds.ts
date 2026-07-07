import type Database from 'better-sqlite3'
import { reorderByDisplayOrder } from './shared/reorder.js'

export interface Feed {
  id: number
  url: string
  title: string | null
  favicon_url: string | null
  group_id: number | null
  last_fetched_at: string | null
  created_at: string
  display_order: number
}

export interface CreateFeedInput {
  url: string
  title?: string
  faviconUrl?: string
  groupId?: number | null
}

export interface UpdateFeedInput {
  url?: string
  title?: string
  faviconUrl?: string
  groupId?: number | null
  lastFetchedAt?: string
}

export class FeedsService {
  constructor(private db: Database.Database) {}

  create(input: CreateFeedInput): Feed {
    // 同グループ内（または ungrouped）の末尾に追加
    const maxOrder = (this.db.prepare(
      'SELECT COALESCE(MAX(display_order), -1) as max_order FROM feeds WHERE group_id IS ?'
    ).get(input.groupId ?? null) as { max_order: number }).max_order
    const displayOrder = maxOrder + 1

    const stmt = this.db.prepare(`
      INSERT INTO feeds (url, title, favicon_url, group_id, display_order)
      VALUES (?, ?, ?, ?, ?)
      RETURNING *
    `)
    return stmt.get(input.url, input.title ?? null, input.faviconUrl ?? null, input.groupId ?? null, displayOrder) as Feed
  }

  findAll(): Feed[] {
    return this.db.prepare('SELECT * FROM feeds ORDER BY display_order ASC, id ASC').all() as Feed[]
  }

  findById(id: number): Feed | null {
    return (this.db.prepare('SELECT * FROM feeds WHERE id = ?').get(id) as Feed) ?? null
  }

  findByGroupId(groupId: number): Feed[] {
    return this.db.prepare('SELECT * FROM feeds WHERE group_id = ? ORDER BY display_order ASC, id ASC').all(groupId) as Feed[]
  }

  reorder(ids: number[]): void {
    if (ids.length === 0) return
    // 全 ID が同一グループに属することを検証
    const placeholders = ids.map(() => '?').join(', ')
    const feeds = this.db.prepare(
      `SELECT DISTINCT group_id FROM feeds WHERE id IN (${placeholders})`
    ).all(...ids) as { group_id: number | null }[]
    if (feeds.length > 1) {
      throw new Error('All feeds must belong to the same group')
    }

    reorderByDisplayOrder(this.db, 'feeds', ids)
  }

  update(id: number, input: UpdateFeedInput): Feed | null {
    const fields: string[] = []
    const values: unknown[] = []

    if (input.url !== undefined) { fields.push('url = ?'); values.push(input.url) }
    if (input.title !== undefined) { fields.push('title = ?'); values.push(input.title) }
    if (input.faviconUrl !== undefined) { fields.push('favicon_url = ?'); values.push(input.faviconUrl) }
    if (input.groupId !== undefined) { fields.push('group_id = ?'); values.push(input.groupId) }
    if (input.lastFetchedAt !== undefined) { fields.push('last_fetched_at = ?'); values.push(input.lastFetchedAt) }

    if (fields.length === 0) return this.findById(id)

    values.push(id)
    const stmt = this.db.prepare(`UPDATE feeds SET ${fields.join(', ')} WHERE id = ? RETURNING *`)
    return (stmt.get(...values) as Feed) ?? null
  }

  remove(id: number): void {
    this.db.prepare('DELETE FROM feeds WHERE id = ?').run(id)
  }
}
