import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema, setDb, closeDb } from '../../db/schema.js'
import { FeedsService } from '../../services/feeds.js'
import { ArticlesService } from '../../services/articles.js'
import { fetchArticleContent } from '../../services/article-content.js'
import { getAIProvider } from '../../services/ai-provider.js'
import articlesRouter, { parseNonNegativeInt } from '../../routes/articles.js'

vi.mock('../../services/article-content.js', () => ({
  fetchArticleContent: vi.fn(),
}))

vi.mock('../../services/ai-provider.js', () => ({
  getAIProvider: vi.fn(),
}))

vi.mock('../../services/ai-config.js', () => ({
  aiConfig: { provider: 'claude' },
}))

const fetchArticleContentMock = vi.mocked(fetchArticleContent)
const getAIProviderMock = vi.mocked(getAIProvider)

let db: Database.Database
let articleId: number

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  setDb(db)
  vi.clearAllMocks()

  const feed = new FeedsService(db).create({ url: 'https://example.com/feed.xml', title: 'Feed' })
  const articles = new ArticlesService(db)
  articles.upsertMany(feed.id, [
    { guid: 'g1', title: 'Hello', link: 'https://example.com/1', summary: 'sum1', content: 'body1', publishedAt: '2026-01-02T00:00:00.000Z' },
    { guid: 'g2', title: 'World', link: 'https://example.com/2', summary: 'sum2', content: 'body2', publishedAt: '2026-01-01T00:00:00.000Z' },
  ])
  articleId = articles.findByFeed(feed.id)[0].id
})

afterEach(() => {
  closeDb()
})

function jsonReq(path: string, body: unknown, method = 'POST') {
  return articlesRouter.request(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

describe('articles ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('published_at 降順で記事一覧を返す', async () => {
      const res = await articlesRouter.request('/')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body).toHaveLength(2)
      expect(body[0].title).toBe('Hello')
    })

    it('unreadOnly=true で未読のみ返す', async () => {
      new ArticlesService(db).markAsRead(articleId)
      const res = await articlesRouter.request('/?unreadOnly=true')
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].is_read).toBe(0)
    })

    it('feedId で絞り込める', async () => {
      const other = new FeedsService(db).create({ url: 'https://other.example.com/feed.xml' })
      const res = await articlesRouter.request(`/?feedId=${other.id}`)
      expect(await res.json()).toEqual([])
    })

    it('limit と offset が効く', async () => {
      const res = await articlesRouter.request('/?limit=1&offset=1')
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].title).toBe('World')
    })
  })

  describe('GET /:id', () => {
    it('記事を返す', async () => {
      const res = await articlesRouter.request(`/${articleId}`)
      expect(res.status).toBe(200)
      expect((await res.json()).id).toBe(articleId)
    })

    it('存在しない id は 404 で { error } を返す', async () => {
      const res = await articlesRouter.request('/9999')
      expect(res.status).toBe(404)
      expect((await res.json()).error).toBeTypeOf('string')
    })
  })

  describe('既読・お気に入り', () => {
    it('POST /:id/read は 204 を返し is_read=1 になる', async () => {
      const res = await articlesRouter.request(`/${articleId}/read`, { method: 'POST' })
      expect(res.status).toBe(204)
      const article = new ArticlesService(db).findById(articleId)
      expect(article?.is_read).toBe(1)
      expect(article?.read_at).toBeTypeOf('string')
    })

    it('POST /:id/unread は 204 を返し is_read=0・read_at=null になる', async () => {
      new ArticlesService(db).markAsRead(articleId)
      const res = await articlesRouter.request(`/${articleId}/unread`, { method: 'POST' })
      expect(res.status).toBe(204)
      const article = new ArticlesService(db).findById(articleId)
      expect(article?.is_read).toBe(0)
      expect(article?.read_at).toBeNull()
    })

    it('POST /:id/favorite と /:id/unfavorite は 204 を返す', async () => {
      expect((await articlesRouter.request(`/${articleId}/favorite`, { method: 'POST' })).status).toBe(204)
      expect(new ArticlesService(db).findById(articleId)?.is_favorite).toBe(1)
      expect((await articlesRouter.request(`/${articleId}/unfavorite`, { method: 'POST' })).status).toBe(204)
      expect(new ArticlesService(db).findById(articleId)?.is_favorite).toBe(0)
    })
  })

  describe('POST /:id/audio', () => {
    it('URL を登録して { ai_audio_url } を返す', async () => {
      const res = await jsonReq(`/${articleId}/audio`, { url: 'https://notebooklm.google.com/x' })
      expect(res.status).toBe(200)
      expect((await res.json()).ai_audio_url).toBe('https://notebooklm.google.com/x')
    })

    it('url 未指定は 400 で { error } を返す', async () => {
      const res = await jsonReq(`/${articleId}/audio`, {})
      expect(res.status).toBe(400)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('不正な URL は 400 を返す', async () => {
      const res = await jsonReq(`/${articleId}/audio`, { url: 'not a url' })
      expect(res.status).toBe(400)
    })

    it('http(s) 以外のスキームは 400 を返す', async () => {
      const res = await jsonReq(`/${articleId}/audio`, { url: 'ftp://example.com/x' })
      expect(res.status).toBe(400)
    })

    it('存在しない記事は 404 を返す', async () => {
      const res = await jsonReq('/9999/audio', { url: 'https://example.com/x' })
      expect(res.status).toBe(404)
    })
  })

  describe('DELETE /:id/audio', () => {
    it('204 を返し ai_audio_url が消える', async () => {
      new ArticlesService(db).setAudioUrl(articleId, 'https://example.com/x')
      const res = await articlesRouter.request(`/${articleId}/audio`, { method: 'DELETE' })
      expect(res.status).toBe(204)
      expect(new ArticlesService(db).findById(articleId)?.ai_audio_url).toBeNull()
    })

    it('存在しない記事は 404 を返す', async () => {
      const res = await articlesRouter.request('/9999/audio', { method: 'DELETE' })
      expect(res.status).toBe(404)
    })
  })

  describe('POST /:id/claude', () => {
    it('不正な action は 400 で { error } を返す', async () => {
      const res = await jsonReq(`/${articleId}/claude`, { action: 'invalid' })
      expect(res.status).toBe(400)
      expect((await res.json()).error).toBeTypeOf('string')
    })

    it('存在しない記事は 404 を返す', async () => {
      const res = await jsonReq('/9999/claude', { action: 'summarize' })
      expect(res.status).toBe(404)
    })

    it('AI を実行して { output, cached: false } を返し、結果が保存される', async () => {
      fetchArticleContentMock.mockResolvedValue('full article text')
      getAIProviderMock.mockReturnValue({ run: vi.fn().mockResolvedValue('要約結果') })

      const res = await jsonReq(`/${articleId}/claude`, { action: 'summarize' })
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual({ output: '要約結果', cached: false })
      expect(new ArticlesService(db).findById(articleId)?.ai_summary).toBe('要約結果')
    })

    it('キャッシュ済みなら provider を呼ばず { output, cached: true } を返す', async () => {
      new ArticlesService(db).saveAiResult(articleId, 'summarize', 'キャッシュ済み要約')
      const res = await jsonReq(`/${articleId}/claude`, { action: 'summarize' })
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual({ output: 'キャッシュ済み要約', cached: true })
      expect(getAIProviderMock).not.toHaveBeenCalled()
    })

    it('force: true はキャッシュを無視して再実行する', async () => {
      new ArticlesService(db).saveAiResult(articleId, 'summarize', '古い要約')
      fetchArticleContentMock.mockResolvedValue('full article text')
      getAIProviderMock.mockReturnValue({ run: vi.fn().mockResolvedValue('新しい要約') })

      const res = await jsonReq(`/${articleId}/claude`, { action: 'summarize', force: true })
      expect(await res.json()).toEqual({ output: '新しい要約', cached: false })
    })

    it('本文取得に失敗したら RSS の content にフォールバックする', async () => {
      fetchArticleContentMock.mockRejectedValue(new Error('fetch failed'))
      const run = vi.fn().mockResolvedValue('要約')
      getAIProviderMock.mockReturnValue({ run })

      const res = await jsonReq(`/${articleId}/claude`, { action: 'summarize' })
      expect(res.status).toBe(200)
      expect(run).toHaveBeenCalledWith('summarize', 'body1')
    })

    it('provider が失敗したら 500 で { error } を返す', async () => {
      fetchArticleContentMock.mockResolvedValue('text')
      getAIProviderMock.mockReturnValue({ run: vi.fn().mockRejectedValue(new Error('AI error')) })

      const res = await jsonReq(`/${articleId}/claude`, { action: 'summarize' })
      expect(res.status).toBe(500)
      expect((await res.json()).error).toBe('AI error')
    })
  })
})

describe('parseNonNegativeInt', () => {
  it('undefined はデフォルト値を返す', () => {
    expect(parseNonNegativeInt(undefined, 50)).toBe(50)
  })

  it('数字文字列をパースして返す', () => {
    expect(parseNonNegativeInt('100', 50)).toBe(100)
    expect(parseNonNegativeInt('0', 50)).toBe(0)
  })

  it('非数値文字列はデフォルト値を返す（NaN ガード）', () => {
    expect(parseNonNegativeInt('abc', 50)).toBe(50)
    expect(parseNonNegativeInt('', 50)).toBe(50)
  })

  it('負の値はデフォルト値を返す', () => {
    expect(parseNonNegativeInt('-5', 50)).toBe(50)
  })

  it('max を超える値は max にクランプする', () => {
    expect(parseNonNegativeInt('99999', 50, 1000)).toBe(1000)
    expect(parseNonNegativeInt('500', 50, 1000)).toBe(500)
  })
})
