import { Hono } from 'hono'
import { FeedsService } from '../services/feeds.js'
import { ArticlesService } from '../services/articles.js'
import { getFaviconUrl } from '../services/rss-fetcher.js'
import { refreshAllFeeds } from '../services/feed-refresher.js'
import { registerFeed, changeFeedUrl, refetchFeed } from '../services/feed-registration.js'
import { getDb } from '../db/schema.js'
import { AppError, errorHandler, isUniqueConstraintError } from '../errors.js'
import type { Feed } from '../services/feeds.js'
import { validateReorderIds } from './shared/validate-reorder-ids.js'

function withGoogleFavicon(feed: Feed): Feed {
  return { ...feed, favicon_url: getFaviconUrl(feed.url) }
}

const app = new Hono()
app.onError(errorHandler)

app.get('/', (c) => {
  return c.json(new FeedsService(getDb()).findAll().map(withGoogleFavicon))
})

app.post('/', async (c) => {
  const { url, groupId } = await c.req.json<{ url: string; groupId?: number }>()
  if (!url?.trim()) throw new AppError('url is required', 400)

  const db = getDb()
  const feed = await registerFeed(url.trim(), groupId, new FeedsService(db), new ArticlesService(db))
  return c.json(feed, 201)
})

app.put('/:id', async (c) => {
  const id = Number(c.req.param('id'))
  const body = await c.req.json<{ url?: string; title?: string; groupId?: number | null }>()

  const db = getDb()
  const feedsService = new FeedsService(db)

  const existing = feedsService.findById(id)
  if (!existing) throw new AppError('Not found', 404)

  // URLが変更された場合は新URLでフィードを再取得してメタ情報を更新する
  if (body.url && body.url.trim() !== existing.url) {
    const updated = await changeFeedUrl(id, body.url.trim(), body.groupId, feedsService, new ArticlesService(db))
    return c.json(updated)
  }

  try {
    const feed = feedsService.update(id, { title: body.title, groupId: body.groupId })
    if (!feed) throw new AppError('Not found', 404)
    return c.json(feed)
  } catch (e: unknown) {
    if (e instanceof AppError) throw e
    if (isUniqueConstraintError(e)) throw new AppError('Feed URL already exists', 409)
    const message = e instanceof Error ? e.message : 'Unknown error'
    throw new AppError(message, 422)
  }
})

app.delete('/:id', (c) => {
  new FeedsService(getDb()).remove(Number(c.req.param('id')))
  return c.body(null, 204)
})

app.patch('/reorder', async (c) => {
  const { ids } = await c.req.json<{ ids: unknown }>()
  const validIds = validateReorderIds(ids)
  try {
    new FeedsService(getDb()).reorder(validIds)
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    throw new AppError(message, 400)
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

  const feed = feedsService.findById(id)
  if (!feed) throw new AppError('Not found', 404)

  const result = await refetchFeed(feed, feedsService, new ArticlesService(db))
  return c.json(result)
})

export default app
