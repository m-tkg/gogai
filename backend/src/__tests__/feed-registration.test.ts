import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { FeedsService } from '../services/feeds.js'
import { ArticlesService } from '../services/articles.js'
import { discoverFeedUrl } from '../services/feed-discovery.js'
import { fetchFeed, type FetchedFeed } from '../services/rss-fetcher.js'
import { registerFeed, changeFeedUrl, refetchFeed } from '../services/feed-registration.js'
import { AppError } from '../errors.js'

vi.mock('../services/feed-discovery.js', () => ({
  discoverFeedUrl: vi.fn(),
}))

vi.mock('../services/rss-fetcher.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../services/rss-fetcher.js')>()
  return { ...actual, fetchFeed: vi.fn() }
})

const discoverFeedUrlMock = vi.mocked(discoverFeedUrl)
const fetchFeedMock = vi.mocked(fetchFeed)

let db: Database.Database
let feedsService: FeedsService
let articlesService: ArticlesService

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  feedsService = new FeedsService(db)
  articlesService = new ArticlesService(db)
  vi.clearAllMocks()
})

afterEach(() => {
  db.close()
})

const FETCHED: FetchedFeed = {
  title: 'Example Feed',
  faviconUrl: 'https://example.com/favicon.ico',
  items: [
    { guid: 'g1', title: 'Hello', link: 'https://example.com/1', publishedAt: '2026-01-01T00:00:00.000Z' },
    { guid: 'g2', title: 'World', link: 'https://example.com/2', publishedAt: '2026-01-02T00:00:00.000Z' },
  ],
}

describe('registerFeed', () => {
  it('URL を検出してフィードを作成し、記事と last_fetched_at を保存する', async () => {
    discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
    fetchFeedMock.mockResolvedValue(FETCHED)

    const feed = await registerFeed('https://example.com', null, feedsService, articlesService)

    expect(feed.url).toBe('https://example.com/feed.xml')
    expect(feed.title).toBe('Example Feed')
    expect(articlesService.findByFeed(feed.id)).toHaveLength(2)
    expect(feedsService.findById(feed.id)?.last_fetched_at).toBeTypeOf('string')
  })

  it('groupId を指定してフィードを作成できる', async () => {
    const groupId = (db.prepare("INSERT INTO groups (name) VALUES ('G') RETURNING id").get() as { id: number }).id
    discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
    fetchFeedMock.mockResolvedValue(FETCHED)

    const feed = await registerFeed('https://example.com', groupId, feedsService, articlesService)
    expect(feed.group_id).toBe(groupId)
  })

  it('フィードが検出できなければ AppError(422) を投げる', async () => {
    discoverFeedUrlMock.mockResolvedValue(null)
    await expect(registerFeed('https://example.com', null, feedsService, articlesService))
      .rejects.toThrow(AppError)
    await expect(registerFeed('https://example.com', null, feedsService, articlesService))
      .rejects.toMatchObject({ status: 422, message: 'RSSフィードが見つかりませんでした' })
  })

  it('URL 重複は AppError(409) を投げる', async () => {
    discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
    fetchFeedMock.mockResolvedValue(FETCHED)
    await registerFeed('https://example.com', null, feedsService, articlesService)

    await expect(registerFeed('https://example.com', null, feedsService, articlesService))
      .rejects.toMatchObject({ status: 409, message: 'Feed URL already exists' })
  })

  it('フィード取得失敗は AppError(422) を投げる', async () => {
    discoverFeedUrlMock.mockResolvedValue('https://example.com/feed.xml')
    fetchFeedMock.mockRejectedValue(new Error('network down'))

    await expect(registerFeed('https://example.com', null, feedsService, articlesService))
      .rejects.toMatchObject({ status: 422, message: 'Failed to fetch feed: network down' })
  })
})

describe('changeFeedUrl', () => {
  it('新 URL を検出・再取得してメタ情報を更新する', async () => {
    const feed = feedsService.create({ url: 'https://old.example.com/feed.xml', title: 'Old' })
    discoverFeedUrlMock.mockResolvedValue('https://new.example.com/feed.xml')
    fetchFeedMock.mockResolvedValue(FETCHED)

    const updated = await changeFeedUrl(feed.id, 'https://new.example.com', undefined, feedsService, articlesService)

    expect(updated?.url).toBe('https://new.example.com/feed.xml')
    expect(updated?.title).toBe('Example Feed')
    expect(articlesService.findByFeed(feed.id)).toHaveLength(2)
  })

  it('groupId も同時に更新できる', async () => {
    const groupId = (db.prepare("INSERT INTO groups (name) VALUES ('G') RETURNING id").get() as { id: number }).id
    const feed = feedsService.create({ url: 'https://old.example.com/feed.xml' })
    discoverFeedUrlMock.mockResolvedValue('https://new.example.com/feed.xml')
    fetchFeedMock.mockResolvedValue(FETCHED)

    const updated = await changeFeedUrl(feed.id, 'https://new.example.com', groupId, feedsService, articlesService)
    expect(updated?.group_id).toBe(groupId)
  })

  it('検出できなければ AppError(422) を投げる', async () => {
    const feed = feedsService.create({ url: 'https://old.example.com/feed.xml' })
    discoverFeedUrlMock.mockResolvedValue(null)

    await expect(changeFeedUrl(feed.id, 'https://new.example.com', undefined, feedsService, articlesService))
      .rejects.toMatchObject({ status: 422 })
  })

  it('変更先 URL が既存フィードと重複したら AppError(409) を投げる', async () => {
    feedsService.create({ url: 'https://a.example.com/feed.xml' })
    const feed = feedsService.create({ url: 'https://b.example.com/feed.xml' })
    discoverFeedUrlMock.mockResolvedValue('https://a.example.com/feed.xml')
    fetchFeedMock.mockResolvedValue(FETCHED)

    await expect(changeFeedUrl(feed.id, 'https://a.example.com', undefined, feedsService, articlesService))
      .rejects.toMatchObject({ status: 409, message: 'Feed URL already exists' })
  })
})

describe('refetchFeed', () => {
  it('既存フィードを再取得し { feed, newArticles } を返す', async () => {
    const feed = feedsService.create({ url: 'https://example.com/feed.xml' })
    fetchFeedMock.mockResolvedValue(FETCHED)

    const result = await refetchFeed(feed, feedsService, articlesService)

    expect(result.feed?.id).toBe(feed.id)
    expect(result.feed?.title).toBe('Example Feed')
    expect(result.newArticles).toBe(2)
    expect(articlesService.findByFeed(feed.id)).toHaveLength(2)
  })

  it('取得失敗は AppError(422) を投げる', async () => {
    const feed = feedsService.create({ url: 'https://example.com/feed.xml' })
    fetchFeedMock.mockRejectedValue(new Error('timeout'))

    await expect(refetchFeed(feed, feedsService, articlesService))
      .rejects.toMatchObject({ status: 422, message: 'Failed to fetch feed: timeout' })
  })
})
