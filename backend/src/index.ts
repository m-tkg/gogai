import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import groupsRouter from './routes/groups.js'
import feedsRouter from './routes/feeds.js'
import articlesRouter from './routes/articles.js'
import { getDb } from './db/schema.js'
import { ArticlesService } from './services/articles.js'
import { mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
mkdirSync(join(__dirname, '../data'), { recursive: true })

const RETENTION_DAYS = 180 // 半年

function purgeOldArticles() {
  const threshold = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000)
  const deleted = new ArticlesService(getDb()).deleteOlderThan(threshold)
  if (deleted > 0) {
    console.log(`[cleanup] ${deleted} 件の古い記事を削除しました（${RETENTION_DAYS}日以前）`)
  }
}

// 起動時 + 24時間ごとにクリーンアップ
purgeOldArticles()
setInterval(purgeOldArticles, 24 * 60 * 60 * 1000)

const app = new Hono()

app.use('*', cors({
  origin: (origin) => origin ?? '*',
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type'],
}))

app.route('/api/groups', groupsRouter)
app.route('/api/feeds', feedsRouter)
app.route('/api/articles', articlesRouter)

app.get('/health', (c) => c.json({ status: 'ok' }))

const port = Number(process.env.PORT ?? 3040)
console.log(`Server running on http://localhost:${port}`)

serve({ fetch: app.fetch, port, hostname: '0.0.0.0' })
