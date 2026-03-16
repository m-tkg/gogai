import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import groupsRouter from './routes/groups.js'
import feedsRouter from './routes/feeds.js'
import articlesRouter from './routes/articles.js'
import { mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
mkdirSync(join(__dirname, '../data'), { recursive: true })

const app = new Hono()

app.use('*', cors({
  origin: ['http://localhost:5173', 'http://localhost:4173'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type'],
}))

app.route('/api/groups', groupsRouter)
app.route('/api/feeds', feedsRouter)
app.route('/api/articles', articlesRouter)

app.get('/health', (c) => c.json({ status: 'ok' }))

const port = Number(process.env.PORT ?? 3000)
console.log(`Server running on http://localhost:${port}`)

serve({ fetch: app.fetch, port })
