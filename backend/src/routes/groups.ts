import { Hono } from 'hono'
import { GroupsService } from '../services/groups.js'
import { getDb } from '../db/schema.js'

const app = new Hono()

app.get('/', (c) => {
  const service = new GroupsService(getDb())
  return c.json(service.findAll())
})

app.post('/', async (c) => {
  const { name } = await c.req.json<{ name: string }>()
  if (!name?.trim()) return c.json({ error: 'name is required' }, 400)
  try {
    const group = new GroupsService(getDb()).create(name.trim())
    return c.json(group, 201)
  } catch {
    return c.json({ error: 'Group name already exists' }, 409)
  }
})

app.put('/:id', async (c) => {
  const id = Number(c.req.param('id'))
  const { name } = await c.req.json<{ name: string }>()
  const group = new GroupsService(getDb()).update(id, name)
  if (!group) return c.json({ error: 'Not found' }, 404)
  return c.json(group)
})

app.delete('/:id', (c) => {
  new GroupsService(getDb()).remove(Number(c.req.param('id')))
  return c.body(null, 204)
})

export default app
