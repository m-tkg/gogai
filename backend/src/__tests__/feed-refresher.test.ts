import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { FeedsService } from '../services/feeds.js'
import { ArticlesService } from '../services/articles.js'
import { GroupsService } from '../services/groups.js'
import { refreshAllFeeds, refreshFeedsByGroupId } from '../services/feed-refresher.js'
import type { FetchedFeed } from '../services/rss-fetcher.js'

let db: Database.Database
let feedsService: FeedsService
let articlesService: ArticlesService
let groupsService: GroupsService

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  feedsService = new FeedsService(db)
  articlesService = new ArticlesService(db)
  groupsService = new GroupsService(db)
})

afterEach(() => {
  db.close()
  vi.restoreAllMocks()
})

const makeFetchedFeed = (title: string): FetchedFeed => ({
  title,
  faviconUrl: null,
  items: [
    { guid: `${title}-1`, title: `Article 1 of ${title}`, link: `https://example.com/1` },
  ],
})

describe('refreshAllFeeds', () => {
  it('フィードが0件の場合はrefreshed=0を返す', async () => {
    const fetchFeedFn = vi.fn()
    const result = await refreshAllFeeds(feedsService, articlesService, fetchFeedFn)
    expect(result.refreshed).toBe(0)
    expect(result.failed).toBe(0)
    expect(fetchFeedFn).not.toHaveBeenCalled()
  })

  it('全フィードを更新できる', async () => {
    feedsService.create({ url: 'https://a.com/feed.xml', title: 'A' })
    feedsService.create({ url: 'https://b.com/feed.xml', title: 'B' })

    const fetchFeedFn = vi.fn((url: string) => Promise.resolve(makeFetchedFeed(url)))
    const result = await refreshAllFeeds(feedsService, articlesService, fetchFeedFn)

    expect(result.refreshed).toBe(2)
    expect(result.failed).toBe(0)
    expect(fetchFeedFn).toHaveBeenCalledTimes(2)
  })

  it('一部のフィードが失敗しても残りを更新する', async () => {
    feedsService.create({ url: 'https://a.com/feed.xml', title: 'A' })
    feedsService.create({ url: 'https://b.com/feed.xml', title: 'B' })

    const fetchFeedFn = vi.fn((url: string) => {
      if (url.includes('a.com')) return Promise.reject(new Error('Network error'))
      return Promise.resolve(makeFetchedFeed(url))
    })

    const result = await refreshAllFeeds(feedsService, articlesService, fetchFeedFn)

    expect(result.refreshed).toBe(1)
    expect(result.failed).toBe(1)
  })

  it('更新後にlast_fetched_atが設定される', async () => {
    const feed = feedsService.create({ url: 'https://a.com/feed.xml', title: 'A' })
    expect(feedsService.findById(feed.id)?.last_fetched_at).toBeNull()

    const fetchFeedFn = vi.fn(() => Promise.resolve(makeFetchedFeed('A')))
    await refreshAllFeeds(feedsService, articlesService, fetchFeedFn)

    expect(feedsService.findById(feed.id)?.last_fetched_at).not.toBeNull()
  })

  it('更新に失敗したフィードのlast_fetched_atは更新されない', async () => {
    const feed = feedsService.create({ url: 'https://a.com/feed.xml', title: 'A' })
    expect(feedsService.findById(feed.id)?.last_fetched_at).toBeNull()

    const fetchFeedFn = vi.fn(() => Promise.reject(new Error('Network error')))
    await refreshAllFeeds(feedsService, articlesService, fetchFeedFn)

    expect(feedsService.findById(feed.id)?.last_fetched_at).toBeNull()
  })
})

describe('refreshFeedsByGroupId', () => {
  it('指定グループのフィードだけを更新する', async () => {
    const group = groupsService.create('Tech')
    feedsService.create({ url: 'https://a.com/feed.xml', title: 'A', groupId: group.id })
    feedsService.create({ url: 'https://b.com/feed.xml', title: 'B', groupId: group.id })
    feedsService.create({ url: 'https://c.com/feed.xml', title: 'C' }) // グループなし

    const fetchFeedFn = vi.fn((url: string) => Promise.resolve(makeFetchedFeed(url)))
    const result = await refreshFeedsByGroupId(group.id, feedsService, articlesService, fetchFeedFn)

    expect(result.refreshed).toBe(2)
    expect(result.failed).toBe(0)
    expect(fetchFeedFn).toHaveBeenCalledTimes(2)
  })

  it('グループにフィードがない場合はrefreshed=0を返す', async () => {
    const group = groupsService.create('Empty')
    const fetchFeedFn = vi.fn()
    const result = await refreshFeedsByGroupId(group.id, feedsService, articlesService, fetchFeedFn)

    expect(result.refreshed).toBe(0)
    expect(result.failed).toBe(0)
    expect(fetchFeedFn).not.toHaveBeenCalled()
  })
})
