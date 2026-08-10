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
  read_at: string | null
  liked_at: string | null
}

export interface ArticleItem {
  guid: string
  title?: string
  link?: string
  summary?: string
  content?: string
  publishedAt?: string
}

export type SortBy = 'published_at' | 'read_at'

// Why: SQL に直接埋め込む ORDER BY 句は、将来 SortBy 値が追加された際に
// 未対応キーが来てもコンパイル時に検出できるよう Record で網羅する。
const ORDER_BY_SQL: Record<SortBy, string> = {
  published_at: 'a.published_at DESC',
  read_at: 'COALESCE(a.read_at, a.published_at) DESC',
}

export interface FeedCount {
  feed_id: number
  total: number
  unread: number
  liked: number
}

export interface FindAllOptions {
  limit: number
  offset: number
  feedId?: number
  groupId?: number
  unreadOnly?: boolean
  likedOnly?: boolean
  sortBy?: SortBy
  includeSecret?: boolean
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
    this.markDuplicateLinksAsRead(feedId)
  }

  private markDuplicateLinksAsRead(feedId: number): void {
    this.db.prepare(`
      UPDATE articles
      SET is_read = 1, read_at = datetime('now')
      WHERE is_read = 0
        AND feed_id = ?
        AND link IS NOT NULL
        AND id IN (
          SELECT a1.id FROM articles a1
          WHERE a1.feed_id = ?
            AND a1.link IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM articles a2
              WHERE a2.link = a1.link
                AND a2.feed_id != a1.feed_id
                AND a2.id < a1.id
            )
        )
    `).run(feedId, feedId)
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
    if (options.likedOnly) {
      conditions.push('a.liked_at IS NOT NULL')
    }
    // groupId 未指定かつ includeSecret でなければシークレットグループを除外
    if (options.groupId === undefined && !options.includeSecret) {
      conditions.push('(f.group_id IS NULL OR g.is_secret = 0)')
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : ''
    values.push(options.limit, options.offset)

    // like 一覧は「いつ好みだと表明したか」順で見せたいので sortBy より優先する
    const orderBy = options.likedOnly ? 'a.liked_at DESC' : ORDER_BY_SQL[options.sortBy ?? 'published_at']

    return this.db.prepare(`
      SELECT a.* FROM articles a
      JOIN feeds f ON a.feed_id = f.id
      LEFT JOIN groups g ON f.group_id = g.id
      ${where}
      ORDER BY ${orderBy}
      LIMIT ? OFFSET ?
    `).all(...values) as Article[]
  }

  // シークレットグループも含む全フィードの集計を返す。
  // サイドバーのシークレット除外はクライアント側の責務（badgeCount(excludingFeedIds:)）。
  countsByFeed(): FeedCount[] {
    return this.db.prepare(`
      SELECT feed_id,
             COUNT(*) AS total,
             SUM(CASE WHEN is_read = 0 THEN 1 ELSE 0 END) AS unread,
             SUM(CASE WHEN liked_at IS NOT NULL THEN 1 ELSE 0 END) AS liked
      FROM articles
      GROUP BY feed_id
    `).all() as FeedCount[]
  }

  findByFeed(feedId: number): Article[] {
    return this.db.prepare('SELECT * FROM articles WHERE feed_id = ? ORDER BY published_at DESC').all(feedId) as Article[]
  }

  findById(id: number): Article | null {
    return (this.db.prepare('SELECT * FROM articles WHERE id = ?').get(id) as Article) ?? null
  }

  markAsRead(id: number, readAt?: string): void {
    this.db.prepare('UPDATE articles SET is_read = 1, read_at = ? WHERE id = ?').run(readAt ?? new Date().toISOString(), id)
  }

  markAsUnread(id: number): void {
    this.db.prepare('UPDATE articles SET is_read = 0, read_at = NULL WHERE id = ?').run(id)
  }

  like(id: number, likedAt?: string): void {
    this.db.prepare('UPDATE articles SET liked_at = ? WHERE id = ?').run(likedAt ?? new Date().toISOString(), id)
  }

  unlike(id: number): void {
    this.db.prepare('UPDATE articles SET liked_at = NULL WHERE id = ?').run(id)
  }

  // like された記事はユーザーの好みシグナルとして蓄積するため、保持期間を過ぎても削除しない
  deleteOlderThan(threshold: Date): number {
    const result = this.db.prepare(
      "DELETE FROM articles WHERE datetime(COALESCE(published_at, created_at)) < datetime(?) AND liked_at IS NULL"
    ).run(threshold.toISOString())
    return result.changes
  }
}
