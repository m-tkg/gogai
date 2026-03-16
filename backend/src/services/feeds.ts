import type Database from 'better-sqlite3'

export interface Feed {
  id: number
  url: string
  title: string | null
  favicon_url: string | null
  group_id: number | null
  last_fetched_at: string | null
  created_at: string
}

export interface CreateFeedInput {
  url: string
  title?: string
  faviconUrl?: string
  groupId?: number | null
}

export interface UpdateFeedInput {
  title?: string
  faviconUrl?: string
  groupId?: number | null
  lastFetchedAt?: string
}

export class FeedsService {
  constructor(private db: Database.Database) {}

  create(input: CreateFeedInput): Feed {
    const stmt = this.db.prepare(`
      INSERT INTO feeds (url, title, favicon_url, group_id)
      VALUES (?, ?, ?, ?)
      RETURNING *
    `)
    return stmt.get(input.url, input.title ?? null, input.faviconUrl ?? null, input.groupId ?? null) as Feed
  }

  findAll(): Feed[] {
    return this.db.prepare('SELECT * FROM feeds ORDER BY created_at DESC').all() as Feed[]
  }

  findById(id: number): Feed | null {
    return (this.db.prepare('SELECT * FROM feeds WHERE id = ?').get(id) as Feed) ?? null
  }

  findByUrl(url: string): Feed | null {
    return (this.db.prepare('SELECT * FROM feeds WHERE url = ?').get(url) as Feed) ?? null
  }

  findByGroupId(groupId: number): Feed[] {
    return this.db.prepare('SELECT * FROM feeds WHERE group_id = ? ORDER BY created_at DESC').all(groupId) as Feed[]
  }

  update(id: number, input: UpdateFeedInput): Feed | null {
    const fields: string[] = []
    const values: unknown[] = []

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
