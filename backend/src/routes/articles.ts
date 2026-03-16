import { Hono } from 'hono'
import { ArticlesService } from '../services/articles.js'
import { getAIProvider } from '../services/ai-provider.js'
import { aiConfig } from '../services/ai-config.js'
import { getDb } from '../db/schema.js'

const app = new Hono()

app.get('/', (c) => {
  const limit = Number(c.req.query('limit') ?? 50)
  const offset = Number(c.req.query('offset') ?? 0)
  const feedId = c.req.query('feedId') ? Number(c.req.query('feedId')) : undefined
  const groupId = c.req.query('groupId') ? Number(c.req.query('groupId')) : undefined
  const unreadOnly = c.req.query('unreadOnly') === 'true'

  const articles = new ArticlesService(getDb()).findAll({ limit, offset, feedId, groupId, unreadOnly })
  return c.json(articles)
})

app.get('/:id', (c) => {
  const article = new ArticlesService(getDb()).findById(Number(c.req.param('id')))
  if (!article) return c.json({ error: 'Not found' }, 404)
  return c.json(article)
})

app.post('/:id/read', (c) => {
  new ArticlesService(getDb()).markAsRead(Number(c.req.param('id')))
  return c.body(null, 204)
})

app.post('/:id/unread', (c) => {
  new ArticlesService(getDb()).markAsUnread(Number(c.req.param('id')))
  return c.body(null, 204)
})

// AI で要約・翻訳
app.post('/:id/claude', async (c) => {
  const id = Number(c.req.param('id'))
  const { action } = await c.req.json<{ action: 'summarize' | 'translate' }>()

  if (!['summarize', 'translate'].includes(action)) {
    return c.json({ error: 'action must be summarize or translate' }, 400)
  }

  const article = new ArticlesService(getDb()).findById(id)
  if (!article) return c.json({ error: 'Not found' }, 404)

  const text = article.content ?? article.summary ?? article.title ?? ''
  if (!text) return c.json({ error: 'Article has no content' }, 422)

  try {
    const provider = getAIProvider(aiConfig)
    const output = await provider.run(action, text)
    return c.json({ output })
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    return c.json({ error: message }, 500)
  }
})

export default app
