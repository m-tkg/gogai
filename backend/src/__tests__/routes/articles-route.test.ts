import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema, setDb, closeDb } from '../../db/schema.js'
import { FeedsService } from '../../services/feeds.js'
import { ArticlesService } from '../../services/articles.js'
import articlesRouter, { parseNonNegativeInt } from '../../routes/articles.js'

let db: Database.Database
let articleId: number

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  setDb(db)

  const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml', title: 'Feed' })
  const articles = new ArticlesService(db)
  articles.upsertMany(feed.id, [
    { guid: 'g1', title: 'Hello', link: 'https://example.com/1', summary: 'sum1', content: 'body1', publishedAt: '2026-01-02T00:00:00.000Z' },
    { guid: 'g2', title: 'World', link: 'https://example.com/2', summary: 'sum2', content: 'body2', publishedAt: '2026-01-01T00:00:00.000Z' },
  ])
  articleId = articles.findByFeed(feed.id)[0].id
})

afterEach(() => {
  closeDb()
})

describe('articles ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('published_at 降順で記事一覧を返す', async () => {
      const res = await articlesRouter.request('/')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body).toHaveLength(2)
      expect(body[0].title).toBe('Hello')
    })

    it('unreadOnly=true で未読のみ返す', async () => {
      new ArticlesService(db).markAsRead(articleId)
      const res = await articlesRouter.request('/?unreadOnly=true')
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].is_read).toBe(0)
    })

    it('feedId で絞り込める', async () => {
      const other = new FeedsService(db).create({ url: 'https://other.example.com/feed.xml' })
      const res = await articlesRouter.request(`/?feedId=${other.id}`)
      expect(await res.json()).toEqual([])
    })

    it('limit と offset が効く', async () => {
      const res = await articlesRouter.request('/?limit=1&offset=1')
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].title).toBe('World')
    })
  })

  describe('GET /counts', () => {
    it('フィードごとの {feed_id, total, unread, favorite} 配列を返す', async () => {
      new ArticlesService(db).markAsRead(articleId)
      new ArticlesService(db).markAsFavorite(articleId)

      const res = await articlesRouter.request('/counts')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0]).toEqual({
        feed_id: expect.any(Number),
        total: 2,
        unread: 1,
        favorite: 1,
      })
    })

    it('counts 追加後も GET /:id（数値 id）が壊れていない', async () => {
      const res = await articlesRouter.request(`/${articleId}`)
      expect(res.status).toBe(200)
      expect((await res.json()).id).toBe(articleId)
    })
  })

  describe('GET /:id', () => {
    it('記事を返す', async () => {
      const res = await articlesRouter.request(`/${articleId}`)
      expect(res.status).toBe(200)
      expect((await res.json()).id).toBe(articleId)
    })

    it('存在しない id は 404 で { error } を返す', async () => {
      const res = await articlesRouter.request('/9999')
      expect(res.status).toBe(404)
      expect((await res.json()).error).toBeTypeOf('string')
    })
  })

  describe('既読・お気に入り', () => {
    it('POST /:id/read は 204 を返し is_read=1 になる', async () => {
      const res = await articlesRouter.request(`/${articleId}/read`, { method: 'POST' })
      expect(res.status).toBe(204)
      const article = new ArticlesService(db).findById(articleId)
      expect(article?.is_read).toBe(1)
      expect(article?.read_at).toBeTypeOf('string')
    })

    it('POST /:id/unread は 204 を返し is_read=0・read_at=null になる', async () => {
      new ArticlesService(db).markAsRead(articleId)
      const res = await articlesRouter.request(`/${articleId}/unread`, { method: 'POST' })
      expect(res.status).toBe(204)
      const article = new ArticlesService(db).findById(articleId)
      expect(article?.is_read).toBe(0)
      expect(article?.read_at).toBeNull()
    })

    it('POST /:id/favorite と /:id/unfavorite は 204 を返す', async () => {
      expect((await articlesRouter.request(`/${articleId}/favorite`, { method: 'POST' })).status).toBe(204)
      expect(new ArticlesService(db).findById(articleId)?.is_favorite).toBe(1)
      expect((await articlesRouter.request(`/${articleId}/unfavorite`, { method: 'POST' })).status).toBe(204)
      expect(new ArticlesService(db).findById(articleId)?.is_favorite).toBe(0)
    })
  })

  describe('削除済み機能のエンドポイントが存在しない', () => {
    it('POST /:id/claude は 404 を返す（AI 機能は削除済み）', async () => {
      const res = await articlesRouter.request(`/${articleId}/claude`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'summarize' }),
      })
      expect(res.status).toBe(404)
    })

    it('POST /:id/audio と DELETE /:id/audio は 404 を返す（音声機能は削除済み）', async () => {
      const post = await articlesRouter.request(`/${articleId}/audio`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: 'https://example.com/x' }),
      })
      expect(post.status).toBe(404)
      const del = await articlesRouter.request(`/${articleId}/audio`, { method: 'DELETE' })
      expect(del.status).toBe(404)
    })
  })
})

describe('parseNonNegativeInt', () => {
  it('undefined はデフォルト値を返す', () => {
    expect(parseNonNegativeInt(undefined, 50)).toBe(50)
  })

  it('数字文字列をパースして返す', () => {
    expect(parseNonNegativeInt('100', 50)).toBe(100)
    expect(parseNonNegativeInt('0', 50)).toBe(0)
  })

  it('非数値文字列はデフォルト値を返す（NaN ガード）', () => {
    expect(parseNonNegativeInt('abc', 50)).toBe(50)
    expect(parseNonNegativeInt('', 50)).toBe(50)
  })

  it('負の値はデフォルト値を返す', () => {
    expect(parseNonNegativeInt('-5', 50)).toBe(50)
  })

  it('max を超える値は max にクランプする', () => {
    expect(parseNonNegativeInt('99999', 50, 1000)).toBe(1000)
    expect(parseNonNegativeInt('500', 50, 1000)).toBe(500)
  })
})
