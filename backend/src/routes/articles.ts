import { Hono } from 'hono'
import { ArticlesService, type SortBy } from '../services/articles.js'
import { getDb } from '../db/schema.js'
import { AppError, errorHandler } from '../errors.js'
import { MAX_ARTICLES_LIMIT } from '../config.js'

const app = new Hono()
app.onError(errorHandler)

export function parseNonNegativeInt(raw: string | undefined, defaultValue: number, max?: number): number {
  if (raw === undefined) return defaultValue
  const n = Number.parseInt(raw, 10)
  if (!Number.isFinite(n) || n < 0) return defaultValue
  return max !== undefined ? Math.min(n, max) : n
}

app.get('/', (c) => {
  const limit = parseNonNegativeInt(c.req.query('limit'), 50, MAX_ARTICLES_LIMIT)
  const offset = parseNonNegativeInt(c.req.query('offset'), 0)
  const feedId = c.req.query('feedId') ? Number(c.req.query('feedId')) : undefined
  const groupId = c.req.query('groupId') ? Number(c.req.query('groupId')) : undefined
  const unreadOnly = c.req.query('unreadOnly') === 'true'
  const includeSecret = c.req.query('includeSecret') === 'true'
  const sortByParam = c.req.query('sortBy')
  const sortBy: SortBy = sortByParam === 'read_at' ? 'read_at' : 'published_at'

  const articles = new ArticlesService(getDb()).findAll({ limit, offset, feedId, groupId, unreadOnly, sortBy, includeSecret })
  return c.json(articles)
})

// 注意: /:id より前に定義しないと :id にマッチして 404 になる
app.get('/counts', (c) => {
  return c.json(new ArticlesService(getDb()).countsByFeed())
})

app.get('/:id', (c) => {
  const article = new ArticlesService(getDb()).findById(Number(c.req.param('id')))
  if (!article) throw new AppError('Not found', 404)
  return c.json(article)
})

app.post('/:id/read', (c) => {
  new ArticlesService(getDb()).markAsRead(Number(c.req.param('id')))
  return c.body(null, 204)
})

app.post('/:id/unread', (c) => {
  new ArticlesService(getDb()).markAsUnread(Number(c.req.param('id')))
  return c.body(null, 204)
})

export default app
