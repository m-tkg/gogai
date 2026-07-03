import { Hono } from 'hono'
import { SettingsService } from '../services/settings.js'
import { getDb } from '../db/schema.js'
import { AppError, errorHandler } from '../errors.js'
import { RETENTION_DAYS_DEFAULT, RETENTION_DAYS_MIN, RETENTION_DAYS_MAX } from '../config.js'

const app = new Hono()
app.onError(errorHandler)

app.get('/', (c) => {
  const settings = new SettingsService(getDb()).getAll()
  return c.json({ retention_days: settings.retention_days ?? RETENTION_DAYS_DEFAULT })
})

app.put('/', async (c) => {
  const body = await c.req.json<{ retention_days?: number }>()
  const days = Number(body.retention_days)

  if (!Number.isInteger(days) || days < RETENTION_DAYS_MIN || days > RETENTION_DAYS_MAX) {
    throw new AppError(`retention_days は ${RETENTION_DAYS_MIN} 以上 ${RETENTION_DAYS_MAX} 以下の整数で指定してください`, 400)
  }

  new SettingsService(getDb()).set('retention_days', days)
  return c.json({ retention_days: days })
})

export default app
