import { Hono } from 'hono'
import { StockCategoriesService } from '../services/stock-categories.js'
import { getDb } from '../db/schema.js'
import { errorHandler } from '../errors.js'
import { validateReorderIds } from './shared/validate-reorder-ids.js'

const app = new Hono()
app.onError(errorHandler)

app.get('/', (c) => {
  const service = new StockCategoriesService(getDb())
  return c.json(service.findAllWithCount())
})

app.patch('/reorder', async (c) => {
  const { ids } = await c.req.json<{ ids: unknown }>()
  new StockCategoriesService(getDb()).reorder(validateReorderIds(ids))
  return c.body(null, 204)
})

export default app
