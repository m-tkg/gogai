import { Hono } from 'hono'
import { StocksService } from '../services/stocks.js'
import { getDb } from '../db/schema.js'
import { AppError, errorHandler } from '../errors.js'

const app = new Hono()
app.onError(errorHandler)

app.get('/', (c) => {
  const categoryIdParam = c.req.query('category_id')
  const categoryId = categoryIdParam !== undefined ? Number(categoryIdParam) : undefined
  const service = new StocksService(getDb())
  return c.json(service.findAll(categoryId))
})

// URL(正規化後)で既存ストックを検索する(共有シート等で追加前に既存か確認する用途)
app.get('/lookup', (c) => {
  const url = c.req.query('url')
  if (!url?.trim()) throw new AppError('url is required', 400)
  const stock = new StocksService(getDb()).findExisting(url)
  return c.json({ stock })
})

app.post('/', async (c) => {
  const { url, title, source, category } = await c.req.json<{
    url: string
    title?: string
    source?: string
    category?: string
  }>()
  if (!url?.trim()) throw new AppError('url is required', 400)

  const { stock, created } = new StocksService(getDb()).create({ url, title, source, category })
  // 既存 URL の再ストックは no-op（新規作成時のみ 201）
  return c.json(stock, created ? 201 : 200)
})

app.put('/:id', async (c) => {
  const id = Number(c.req.param('id'))
  const { title, category } = await c.req.json<{ title: string; category: string }>()
  if (!category?.trim()) throw new AppError('category is required', 400)
  const stock = new StocksService(getDb()).update(id, { title, category })
  if (!stock) throw new AppError('Not found', 404)
  return c.json(stock)
})

app.delete('/:id', (c) => {
  new StocksService(getDb()).remove(Number(c.req.param('id')))
  return c.body(null, 204)
})

app.put('/:id/summary', async (c) => {
  const id = Number(c.req.param('id'))
  const { summary } = await c.req.json<{ summary: string }>()
  const updated = new StocksService(getDb()).setSummary(id, summary)
  if (!updated) throw new AppError('Not found', 404)
  return c.body(null, 204)
})

app.get('/:id/translation', (c) => {
  const id = Number(c.req.param('id'))
  const translation = new StocksService(getDb()).getTranslation(id)
  if (!translation) throw new AppError('Not found', 404)
  return c.json(translation)
})

app.put('/:id/translation', async (c) => {
  const id = Number(c.req.param('id'))
  const { segments } = await c.req.json<{ segments: string }>()
  new StocksService(getDb()).upsertTranslation(id, segments)
  return c.body(null, 204)
})

app.delete('/:id/translation', (c) => {
  const id = Number(c.req.param('id'))
  new StocksService(getDb()).deleteTranslation(id)
  return c.body(null, 204)
})

export default app
