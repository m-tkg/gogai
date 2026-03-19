import { Hono } from 'hono'
import { GroupsService } from '../services/groups.js'
import { FeedsService } from '../services/feeds.js'
import { ArticlesService } from '../services/articles.js'
import { refreshFeedsByGroupId } from '../services/feed-refresher.js'
import { getDb } from '../db/schema.js'

const app = new Hono()

app.get('/', (c) => {
  const service = new GroupsService(getDb())
  return c.json(service.findAll())
})

app.post('/', async (c) => {
  const { name, is_secret } = await c.req.json<{ name: string; is_secret?: number }>()
  if (!name?.trim()) return c.json({ error: 'name is required' }, 400)
  try {
    const group = new GroupsService(getDb()).create(name.trim(), is_secret ?? 0)
    return c.json(group, 201)
  } catch {
    return c.json({ error: 'Group name already exists' }, 409)
  }
})

app.put('/:id', async (c) => {
  const id = Number(c.req.param('id'))
  const { name, is_secret } = await c.req.json<{ name: string; is_secret?: number }>()
  const group = new GroupsService(getDb()).update(id, name, is_secret)
  if (!group) return c.json({ error: 'Not found' }, 404)
  return c.json(group)
})

app.delete('/:id', (c) => {
  new GroupsService(getDb()).remove(Number(c.req.param('id')))
  return c.body(null, 204)
})

app.patch('/reorder', async (c) => {
  const { ids } = await c.req.json<{ ids: number[] }>()
  if (!Array.isArray(ids)) return c.json({ error: 'ids must be an array' }, 400)
  new GroupsService(getDb()).reorder(ids)
  return c.body(null, 204)
})

// グループ内の全フィードを一括リフレッシュ
app.post('/:id/refresh', async (c) => {
  const id = Number(c.req.param('id'))
  const db = getDb()
  const group = new GroupsService(db).findById(id)
  if (!group) return c.json({ error: 'Not found' }, 404)
  const result = await refreshFeedsByGroupId(id, new FeedsService(db), new ArticlesService(db))
  return c.json(result)
})

export default app
