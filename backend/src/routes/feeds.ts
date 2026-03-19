import { Hono } from 'hono'
import { FeedsService } from '../services/feeds.js'
import { ArticlesService } from '../services/articles.js'
import { fetchFeed, getFaviconUrl } from '../services/rss-fetcher.js'
import { discoverFeedUrl } from '../services/feed-discovery.js'
import { refreshAllFeeds } from '../services/feed-refresher.js'
import { getDb } from '../db/schema.js'
import type { Feed } from '../services/feeds.js'

function withGoogleFavicon(feed: Feed): Feed {
  return { ...feed, favicon_url: getFaviconUrl(feed.url) }
}

const app = new Hono()

app.get('/', (c) => {
  return c.json(new FeedsService(getDb()).findAll().map(withGoogleFavicon))
})

app.post('/', async (c) => {
  const { url, groupId } = await c.req.json<{ url: string; groupId?: number }>()
  if (!url?.trim()) return c.json({ error: 'url is required' }, 400)

  const db = getDb()
  const feedsService = new FeedsService(db)
  const articlesService = new ArticlesService(db)

  try {
    // URLからRSSフィードを自動検出
    const feedUrl = await discoverFeedUrl(url.trim())
    if (!feedUrl) {
      return c.json({ error: 'RSSフィードが見つかりませんでした' }, 422)
    }

    // RSSフィードを取得してメタ情報を取得
    const fetched = await fetchFeed(feedUrl)

    const feed = feedsService.create({
      url: feedUrl,
      title: fetched.title,
      faviconUrl: fetched.faviconUrl !== null ? fetched.faviconUrl : undefined,
      groupId: groupId ?? null,
    })

    // 記事を保存
    articlesService.upsertMany(feed.id, fetched.items)
    feedsService.update(feed.id, { lastFetchedAt: new Date().toISOString() })

    return c.json(feed, 201)
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    if (message.includes('UNIQUE constraint')) {
      return c.json({ error: 'Feed URL already exists' }, 409)
    }
    return c.json({ error: `Failed to fetch feed: ${message}` }, 422)
  }
})

app.put('/:id', async (c) => {
  const id = Number(c.req.param('id'))
  const body = await c.req.json<{ url?: string; title?: string; groupId?: number | null }>()

  const db = getDb()
  const feedsService = new FeedsService(db)
  const articlesService = new ArticlesService(db)

  const existing = feedsService.findById(id)
  if (!existing) return c.json({ error: 'Not found' }, 404)

  // URLが変更された場合は新URLでフィードを再取得してメタ情報を更新する
  if (body.url && body.url.trim() !== existing.url) {
    const newUrl = body.url.trim()
    try {
      const feedUrl = await discoverFeedUrl(newUrl)
      if (!feedUrl) return c.json({ error: 'RSSフィードが見つかりませんでした' }, 422)

      const fetched = await fetchFeed(feedUrl)
      articlesService.upsertMany(id, fetched.items)
      const updated = feedsService.update(id, {
        url: feedUrl,
        title: fetched.title,
        faviconUrl: fetched.faviconUrl !== null ? fetched.faviconUrl : undefined,
        lastFetchedAt: new Date().toISOString(),
        groupId: body.groupId,
      })
      return c.json(updated)
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : 'Unknown error'
      if (message.includes('UNIQUE constraint')) {
        return c.json({ error: 'Feed URL already exists' }, 409)
      }
      return c.json({ error: `Failed to fetch feed: ${message}` }, 422)
    }
  }

  try {
    const feed = feedsService.update(id, { title: body.title, groupId: body.groupId })
    if (!feed) return c.json({ error: 'Not found' }, 404)
    return c.json(feed)
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    if (message.includes('UNIQUE constraint')) {
      return c.json({ error: 'Feed URL already exists' }, 409)
    }
    return c.json({ error: message }, 422)
  }
})

app.delete('/:id', (c) => {
  new FeedsService(getDb()).remove(Number(c.req.param('id')))
  return c.body(null, 204)
})

app.patch('/reorder', async (c) => {
  const { ids } = await c.req.json<{ ids: number[] }>()
  if (!Array.isArray(ids)) return c.json({ error: 'ids must be an array' }, 400)
  try {
    new FeedsService(getDb()).reorder(ids)
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    return c.json({ error: message }, 400)
  }
  return c.body(null, 204)
})

// 全フィードを一括リフレッシュ
// NOTE: /:id/refresh より前に定義しないと /refresh-all が id=refresh として解釈されるため順序が重要
app.post('/refresh-all', async (c) => {
  const db = getDb()
  const result = await refreshAllFeeds(new FeedsService(db), new ArticlesService(db))
  return c.json(result)
})

// フィードを手動でリフレッシュ
app.post('/:id/refresh', async (c) => {
  const id = Number(c.req.param('id'))
  const db = getDb()
  const feedsService = new FeedsService(db)
  const articlesService = new ArticlesService(db)

  const feed = feedsService.findById(id)
  if (!feed) return c.json({ error: 'Not found' }, 404)

  try {
    const fetched = await fetchFeed(feed.url)
    articlesService.upsertMany(feed.id, fetched.items)
    const updated = feedsService.update(feed.id, {
      title: fetched.title,
      faviconUrl: fetched.faviconUrl !== null ? fetched.faviconUrl : undefined,
      lastFetchedAt: new Date().toISOString(),
    })
    return c.json({ feed: updated, newArticles: fetched.items.length })
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    return c.json({ error: `Failed to fetch feed: ${message}` }, 422)
  }
})

export default app
