import { Hono } from 'hono'
import { SettingsService } from '../services/settings.js'
import { getDb } from '../db/schema.js'

const RETENTION_MIN = 3
const RETENTION_MAX = 180

const app = new Hono()

app.get('/', (c) => {
  const settings = new SettingsService(getDb()).getAll()
  return c.json({ retention_days: settings.retention_days ?? 180 })
})

app.put('/', async (c) => {
  const body = await c.req.json<{ retention_days?: number }>()
  const days = Number(body.retention_days)

  if (!Number.isInteger(days) || days < RETENTION_MIN || days > RETENTION_MAX) {
    return c.json({ error: `retention_days は ${RETENTION_MIN} 以上 ${RETENTION_MAX} 以下の整数で指定してください` }, 400)
  }

  new SettingsService(getDb()).set('retention_days', days)
  return c.json({ retention_days: days })
})

export default app
