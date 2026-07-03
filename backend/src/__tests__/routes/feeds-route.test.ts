import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema, setDb, closeDb } from '../../db/schema.js'
import { FeedsService } from '../../services/feeds.js'
import { ArticlesService } from '../../services/articles.js'
import { getFaviconUrl } from '../../services/rss-fetcher.js'
import { discoverFeedUrl } from '../../services/feed-discovery.js'
import { fetchFeed, type FetchedFeed } from '../../services/rss-fetcher.js'
import feedsRouter from '../../routes/feeds.js'

vi.mock('../../services/feed-discovery.js', () => ({
  discoverFeedUrl: vi.fn(),
}))

vi.mock('../../services/rss-fetcher.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../services/rss-fetcher.js')>()
  return { ...actual, fetchFeed: vi.fn() }
})

const discoverFeedUrlMock = vi.mocked(discoverFeedUrl)
const fetchFeedMock = vi.mocked(fetchFeed)

let db: Database.Database

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  setDb(db)
  vi.clearAllMocks()
})

afterEach(() => {
  closeDb()
})

function jsonReq(path: string, body: unknown, method = 'POST') {
  return feedsRouter.request(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

const FETCHED: FetchedFeed = {
  title: 'Example Feed',
  faviconUrl: 'https://example.com/favicon.ico',
  items: [
    { guid: 'g1', title: 'Hello', link: 'https://example.com/1', publishedAt: '2026-01-01T00:00:00.000Z' },
    { guid: 'g2', title: 'World', link: 'https://example.com/2', publishedAt: '2026-01-02T00:00:00.000Z' },
  ],
}

describe('feeds ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('空配列を返す', async () => {
      const res = await feedsRouter.request('/')
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual([])
    })

    it('favicon_url は Google favicon サービス URL に差し替えられる', async () => {
      new FeedsService(db).create({ url: 'https://example.com/feed.xml', title: 'X' })
      const res = await feedsRouter.request('/')
      const body = await res.json()
      expect(body[0].favicon_url).toBe(getFaviconUrl('https://example.com/feed.xml'))
    })
  })

  describe('POST /', () => {
    it('url 未指定は 400 で { error } を返す', async () => {
      const res = await jsonReq('/', {})
      expect(res.status).toBe(400)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('フィードが検出できなければ 422 で { error } を返す', async () => {
      discoverFeedUrlMock.mockResolvedValue(null)
      const res = await jsonReq('/', { url: 'https://example.com' })
      expect(res.status).toBe(422)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('201 で作成したフィードを返し、記事と last_fetched_at が保存される', async () => {
      discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
      fetchFeedMock.mockResolvedValue(FETCHED)

      const res = await jsonReq('/', { url: 'https://example.com', groupId: null })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.url).toBe('https://example.com/feed.xml')
      expect(body.title).toBe('Example Feed')

      const articles = new ArticlesService(db).findByFeed(body.id)
      expect(articles).toHaveLength(2)
      expect(new FeedsService(db).findById(body.id)?.last_fetched_at).toBeTypeOf('string')
    })

    it('重複 URL は 409 で { error } を返す', async () => {
      discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
      fetchFeedMock.mockResolvedValue(FETCHED)
      await jsonReq('/', { url: 'https://example.com' })
      const res = await jsonReq('/', { url: 'https://example.com' })
      expect(res.status).toBe(409)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('フィード取得失敗は 422 で { error } を返す', async () => {
      discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
      fetchFeedMock.mockRejectedValue(new Error('network down'))
      const res = await jsonReq('/', { url: 'https://example.com' })
      expect(res.status).toBe(422)
      expect((await res.json()).error).toContain('network down')
    })
  })

  describe('PUT /:id', () => {
    it('存在しない id は 404 で { error } を返す', async () => {
      const res = await jsonReq('/999', { title: 'X' }, 'PUT')
      expect(res.status).toBe(404)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('title のみ更新できる（URL 変更なしなら再取得しない）', async () => {
      const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml', title: 'Old' })
      const res = await jsonReq(`/${feed.id}`, { title: 'New' }, 'PUT')
      expect(res.status).toBe(200)
      expect((await res.json()).title).toBe('New')
      expect(fetchFeedMock).not.toHaveBeenCalled()
    })

    it('groupId を null に更新できる（グループ解除）', async () => {
      const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml', groupId: null })
      const res = await jsonReq(`/${feed.id}`, { groupId: null }, 'PUT')
      expect(res.status).toBe(200)
      expect((await res.json()).group_id).toBeNull()
    })

    it('URL 変更時は再検出・再取得してメタ情報を更新する', async () => {
      const feed = new FeedsService(db).create({ url: 'https://old.example.com/feed.xml', title: 'Old' })
      discoverFeedUrlMock.mockResolvedValue('https://new.example.com/feed.xml')
      fetchFeedMock.mockResolvedValue(FETCHED)

      const res = await jsonReq(`/${feed.id}`, { url: 'https://new.example.com' }, 'PUT')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.url).toBe('https://new.example.com/feed.xml')
      expect(body.title).toBe('Example Feed')
      expect(new ArticlesService(db).findByFeed(feed.id)).toHaveLength(2)
    })

    it('URL 変更時に検出できなければ 422 を返す', async () => {
      const feed = new FeedsService(db).create({ url: 'https://old.example.com/feed.xml' })
      discoverFeedUrlMock.mockResolvedValue(null)
      const res = await jsonReq(`/${feed.id}`, { url: 'https://new.example.com' }, 'PUT')
      expect(res.status).toBe(422)
    })

    it('URL 変更先が既存フィードと重複したら 409 を返す', async () => {
      const svc = new FeedsService(db)
      svc.create({ url: 'https://a.example.com/feed.xml' })
      const feed = svc.create({ url: 'https://b.example.com/feed.xml' })
      discoverFeedUrlMock.mockResolvedValue('https://a.example.com/feed.xml')
      fetchFeedMock.mockResolvedValue(FETCHED)

      const res = await jsonReq(`/${feed.id}`, { url: 'https://a.example.com' }, 'PUT')
      expect(res.status).toBe(409)
      expect((await res.json()).error).toBeTypeOf('string')
    })
  })

  describe('DELETE /:id', () => {
    it('204 を返し、フィードが消える', async () => {
      const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml' })
      const res = await feedsRouter.request(`/${feed.id}`, { method: 'DELETE' })
      expect(res.status).toBe(204)
      expect(new FeedsService(db).findById(feed.id)).toBeNull()
    })
  })

  describe('PATCH /reorder', () => {
    it('ids の順に並び替えて 204 を返す', async () => {
      const svc = new FeedsService(db)
      const a = svc.create({ url: 'https://a.example.com/feed.xml' })
      const b = svc.create({ url: 'https://b.example.com/feed.xml' })
      const res = await jsonReq('/reorder', { ids: [b.id, a.id] }, 'PATCH')
      expect(res.status).toBe(204)
      const list = svc.findAll()
      expect(list.map((f) => f.id)).toEqual([b.id, a.id])
    })

    it('ids が配列でなければ 400 で { error } を返す', async () => {
      const res = await jsonReq('/reorder', { ids: 'x' }, 'PATCH')
      expect(res.status).toBe(400)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('異なるグループのフィードが混在したら 400 を返す', async () => {
      const groupId = (db.prepare("INSERT INTO groups (name) VALUES ('G') RETURNING id").get() as { id: number }).id
      const svc = new FeedsService(db)
      const a = svc.create({ url: 'https://a.example.com/feed.xml', groupId })
      const b = svc.create({ url: 'https://b.example.com/feed.xml', groupId: null })
      const res = await jsonReq('/reorder', { ids: [b.id, a.id] }, 'PATCH')
      expect(res.status).toBe(400)
      expect((await res.json()).error).toBeTypeOf('string')
    })
  })

  describe('POST /refresh-all', () => {
    it('全フィードを再取得し { refreshed, failed } を返す', async () => {
      const svc = new FeedsService(db)
      svc.create({ url: 'https://a.example.com/feed.xml' })
      svc.create({ url: 'https://b.example.com/feed.xml' })
      fetchFeedMock.mockResolvedValue(FETCHED)

      const res = await feedsRouter.request('/refresh-all', { method: 'POST' })
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.refreshed).toBe(2)
      expect(body.failed).toBe(0)
    })
  })

  describe('POST /:id/refresh', () => {
    it('存在しない id は 404 で { error } を返す', async () => {
      const res = await feedsRouter.request('/999/refresh', { method: 'POST' })
      expect(res.status).toBe(404)
    })

    it('再取得して { feed, newArticles } を返す', async () => {
      const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml' })
      fetchFeedMock.mockResolvedValue(FETCHED)

      const res = await feedsRouter.request(`/${feed.id}/refresh`, { method: 'POST' })
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.feed.id).toBe(feed.id)
      expect(body.newArticles).toBe(2)
    })

    it('取得失敗は 422 で { error } を返す', async () => {
      const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml' })
      fetchFeedMock.mockRejectedValue(new Error('timeout'))
      const res = await feedsRouter.request(`/${feed.id}/refresh`, { method: 'POST' })
      expect(res.status).toBe(422)
      expect((await res.json()).error).toContain('timeout')
    })
  })
})
