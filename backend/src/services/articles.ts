import type Database from 'better-sqlite3'

export interface Article {
  id: number
  feed_id: number
  guid: string
  title: string | null
  link: string | null
  summary: string | null
  content: string | null
  published_at: string | null
  is_read: number
  created_at: string
  ai_summary: string | null
  ai_translation: string | null
}

export interface ArticleItem {
  guid: string
  title?: string
  link?: string
  summary?: string
  content?: string
  publishedAt?: string
}

export interface FindAllOptions {
  limit: number
  offset: number
  feedId?: number
  groupId?: number
  unreadOnly?: boolean
}

export class ArticlesService {
  constructor(private db: Database.Database) {}

  upsertMany(feedId: number, items: ArticleItem[]): void {
    const stmt = this.db.prepare(`
      INSERT INTO articles (feed_id, guid, title, link, summary, content, published_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(feed_id, guid) DO UPDATE SET
        title = excluded.title,
        link = excluded.link,
        summary = excluded.summary,
        content = excluded.content,
        published_at = excluded.published_at
    `)
    const upsert = this.db.transaction((items: ArticleItem[]) => {
      for (const item of items) {
        stmt.run(
          feedId,
          item.guid,
          item.title ?? null,
          item.link ?? null,
          item.summary ?? null,
          item.content ?? null,
          item.publishedAt ?? null
        )
      }
    })
    upsert(items)
  }

  findAll(options: FindAllOptions): Article[] {
    const conditions: string[] = []
    const values: unknown[] = []

    if (options.feedId !== undefined) {
      conditions.push('a.feed_id = ?')
      values.push(options.feedId)
    }
    if (options.groupId !== undefined) {
      conditions.push('f.group_id = ?')
      values.push(options.groupId)
    }
    if (options.unreadOnly) {
      conditions.push('a.is_read = 0')
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : ''
    values.push(options.limit, options.offset)

    return this.db.prepare(`
      SELECT a.* FROM articles a
      JOIN feeds f ON a.feed_id = f.id
      ${where}
      ORDER BY a.published_at DESC
      LIMIT ? OFFSET ?
    `).all(...values) as Article[]
  }

  findByFeed(feedId: number): Article[] {
    return this.db.prepare('SELECT * FROM articles WHERE feed_id = ? ORDER BY published_at DESC').all(feedId) as Article[]
  }

  findById(id: number): Article | null {
    return (this.db.prepare('SELECT * FROM articles WHERE id = ?').get(id) as Article) ?? null
  }

  markAsRead(id: number): void {
    this.db.prepare('UPDATE articles SET is_read = 1 WHERE id = ?').run(id)
  }

  markAsUnread(id: number): void {
    this.db.prepare('UPDATE articles SET is_read = 0 WHERE id = ?').run(id)
  }

  saveAiResult(id: number, action: 'summarize' | 'translate', text: string): void {
    const col = action === 'summarize' ? 'ai_summary' : 'ai_translation'
    this.db.prepare(`UPDATE articles SET ${col} = ? WHERE id = ?`).run(text, id)
  }

  deleteOlderThan(threshold: Date): number {
    const result = this.db.prepare(
      "DELETE FROM articles WHERE datetime(COALESCE(published_at, created_at)) < datetime(?)"
    ).run(threshold.toISOString())
    return result.changes
  }
}
