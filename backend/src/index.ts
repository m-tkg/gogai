import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import groupsRouter from './routes/groups.js'
import feedsRouter from './routes/feeds.js'
import articlesRouter from './routes/articles.js'
import settingsRouter from './routes/settings.js'
import adminRouter from './routes/admin.js'
import { getDb } from './db/schema.js'
import { ArticlesService } from './services/articles.js'
import { SettingsService } from './services/settings.js'
import { FeedsService } from './services/feeds.js'
import { refreshAllFeeds } from './services/feed-refresher.js'
import { runSafely } from './utils/safe-run.js'
import { errorHandler } from './errors.js'
import { RETENTION_DAYS_DEFAULT } from './config.js'
import { mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
mkdirSync(join(__dirname, '../data'), { recursive: true })

function purgeOldArticles() {
  const days = new SettingsService(getDb()).get('retention_days', RETENTION_DAYS_DEFAULT)
  const threshold = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
  const deleted = new ArticlesService(getDb()).deleteOlderThan(threshold)
  if (deleted > 0) {
    console.log(`[cleanup] ${deleted} 件の古い記事を削除しました（${days}日以前）`)
  }
}

// 起動時 + 24時間ごとにクリーンアップ
purgeOldArticles()
setInterval(() => runSafely('cleanup', purgeOldArticles), 24 * 60 * 60 * 1000)

// 5分ごとにフィードを自動更新（起動直後は不要なためインターバルのみ）
async function autoRefreshFeeds() {
  const db = getDb()
  const { refreshed, failed } = await refreshAllFeeds(new FeedsService(db), new ArticlesService(db))
  if (refreshed > 0 || failed > 0) {
    console.log(`[feed-refresher] ${refreshed} 件更新、${failed} 件失敗`)
  }
}

setInterval(() => runSafely('feed-refresher', autoRefreshFeeds), 5 * 60 * 1000)

const app = new Hono()
app.onError(errorHandler)

app.use('*', cors({
  origin: (origin) => origin ?? '*',
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type'],
}))

app.route('/api/groups', groupsRouter)
app.route('/api/feeds', feedsRouter)
app.route('/api/articles', articlesRouter)
app.route('/api/settings', settingsRouter)
app.route('/api/admin', adminRouter)

app.get('/health', (c) => c.json({ status: 'ok' }))

const port = Number(process.env.PORT ?? 3040)
console.log(`Server running on http://localhost:${port}`)

serve({ fetch: app.fetch, port, hostname: '0.0.0.0' })
