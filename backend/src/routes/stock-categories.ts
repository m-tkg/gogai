import { Hono } from 'hono'
import { StockCategoriesService } from '../services/stock-categories.js'
import { getDb } from '../db/schema.js'
import { AppError, errorHandler } from '../errors.js'

const app = new Hono()
app.onError(errorHandler)

app.get('/', (c) => {
  const service = new StockCategoriesService(getDb())
  return c.json(service.findAllWithCount())
})

app.patch('/reorder', async (c) => {
  const { ids } = await c.req.json<{ ids: number[] }>()
  if (!Array.isArray(ids) || !ids.every(Number.isInteger)) {
    throw new AppError('ids must be an array of integers', 400)
  }
  new StockCategoriesService(getDb()).reorder(ids)
  return c.body(null, 204)
})

export default app
