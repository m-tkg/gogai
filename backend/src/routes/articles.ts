import { Hono } from 'hono'
import { ArticlesService, type SortBy } from '../services/articles.js'
import { getAIProvider } from '../services/ai-provider.js'
import { aiConfig } from '../services/ai-config.js'
import { fetchArticleContent } from '../services/article-content.js'
import { getDb } from '../db/schema.js'

const app = new Hono()

app.get('/', (c) => {
  const limit = Number(c.req.query('limit') ?? 50)
  const offset = Number(c.req.query('offset') ?? 0)
  const feedId = c.req.query('feedId') ? Number(c.req.query('feedId')) : undefined
  const groupId = c.req.query('groupId') ? Number(c.req.query('groupId')) : undefined
  const unreadOnly = c.req.query('unreadOnly') === 'true'
  const sortByParam = c.req.query('sortBy')
  const sortBy: SortBy = sortByParam === 'read_at' ? 'read_at' : 'published_at'

  const articles = new ArticlesService(getDb()).findAll({ limit, offset, feedId, groupId, unreadOnly, sortBy })
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
  const { action, force } = await c.req.json<{ action: 'summarize' | 'translate'; force?: boolean }>()

  if (!['summarize', 'translate'].includes(action)) {
    return c.json({ error: 'action must be summarize or translate' }, 400)
  }

  const articlesService = new ArticlesService(getDb())
  const article = articlesService.findById(id)
  if (!article) return c.json({ error: 'Not found' }, 404)

  // キャッシュ確認（force=true の場合はスキップ）
  if (!force) {
    const cached = action === 'summarize' ? article.ai_summary : article.ai_translation
    if (cached) return c.json({ output: cached, cached: true })
  }

  // 記事リンクから本文を取得、失敗時は RSS の content/summary にフォールバック
  let text = ''
  if (article.link) {
    try {
      text = await fetchArticleContent(article.link)
    } catch {
      // フォールバック
    }
  }
  if (!text) {
    text = article.content ?? article.summary ?? article.title ?? ''
  }
  if (!text) return c.json({ error: 'Article has no content' }, 422)

  try {
    const provider = getAIProvider(aiConfig)
    const output = await provider.run(action, text)
    articlesService.saveAiResult(id, action, output)
    return c.json({ output, cached: false })
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Unknown error'
    return c.json({ error: message }, 500)
  }
})

export default app
