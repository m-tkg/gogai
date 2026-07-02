import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema, setDb, closeDb } from '../../db/schema.js'
import stockCategoriesRouter from '../../routes/stock-categories.js'
import stocksRouter from '../../routes/stocks.js'

let db: Database.Database

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  setDb(db)
})

afterEach(() => {
  closeDb()
})

function postJson(path: string, body: unknown, method = 'POST') {
  return stocksRouter.request(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

function patchJson(path: string, body: unknown) {
  return stockCategoriesRouter.request(path, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

describe('stock-categories ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('カテゴリがなければ空配列を返す', async () => {
      const res = await stockCategoriesRouter.request('/')
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual([])
    })

    it('ストック作成で生まれたカテゴリを stock_count 付きで返す', async () => {
      await postJson('/', { url: 'https://example.com/a', source: 'Tech' })
      await postJson('/', { url: 'https://example.com/b', source: 'Tech' })
      const res = await stockCategoriesRouter.request('/')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].name).toBe('Tech')
      expect(body[0].stock_count).toBe(2)
    })

    it('display_order の昇順で返す', async () => {
      await postJson('/', { url: 'https://example.com/a', source: 'B' })
      await postJson('/', { url: 'https://example.com/b', source: 'A' })
      const res = await stockCategoriesRouter.request('/')
      const body = await res.json()
      expect(body.map((c: { name: string }) => c.name)).toEqual(['B', 'A'])
    })
  })

  describe('PATCH /reorder', () => {
    it('ids の順に並び替えて 204 を返す', async () => {
      await postJson('/', { url: 'https://example.com/a', source: 'A' })
      await postJson('/', { url: 'https://example.com/b', source: 'B' })
      const categories = await (await stockCategoriesRouter.request('/')).json()
      const [a, b] = categories
      const res = await patchJson('/reorder', { ids: [b.id, a.id] })
      expect(res.status).toBe(204)
      const list = await (await stockCategoriesRouter.request('/')).json()
      expect(list.map((c: { name: string }) => c.name)).toEqual([b.name, a.name])
    })

    it('ids が整数配列でなければ 400 で { error } を返す', async () => {
      const res = await patchJson('/reorder', { ids: ['x'] })
      expect(res.status).toBe(400)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })
  })
})
