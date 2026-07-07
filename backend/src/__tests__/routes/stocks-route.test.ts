import { describe, it, expect } from 'vitest'
import stocksRouter from '../../routes/stocks.js'
import stockCategoriesRouter from '../../routes/stock-categories.js'
import { useTestDb } from '../helpers/db.js'
import { jsonRequest } from '../helpers/http.js'

useTestDb()

function postJson(path: string, body: unknown, method = 'POST') {
  return jsonRequest(stocksRouter, path, body, method)
}

describe('stocks ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('ストックがなければ空配列を返す', async () => {
      const res = await stocksRouter.request('/')
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual([])
    })

    it('作成済みストックを category_name / has_translation 付きで返す', async () => {
      await postJson('/', { url: 'https://example.com/a', title: 'A', source: 'Tech' })
      const res = await stocksRouter.request('/')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].url).toBe('https://example.com/a')
      expect(body[0].title).toBe('A')
      expect(body[0].category_name).toBe('Tech')
      expect(body[0].has_translation).toBe(false)
      expect(body[0].summary).toBeNull()
      // segments 本体は一覧に含めない
      expect(body[0].segments).toBeUndefined()
    })

    it('category_id で絞り込める', async () => {
      await postJson('/', { url: 'https://example.com/a', source: 'Tech' })
      await postJson('/', { url: 'https://example.com/b', source: 'News' })
      const categories = await (await stockCategoriesRouter.request('/')).json()
      const tech = categories.find((c: { name: string }) => c.name === 'Tech')
      const res = await stocksRouter.request(`/?category_id=${tech.id}`)
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].url).toBe('https://example.com/a')
    })
  })

  describe('POST /', () => {
    it('201 で作成したストックを返す（category 省略時は source をコピー）', async () => {
      const res = await postJson('/', { url: 'https://example.com/a', title: 'A', source: 'Tech' })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.id).toBeTypeOf('number')
      expect(body.url).toBe('https://example.com/a')
      expect(body.source).toBe('Tech')
      expect(body.category_name).toBe('Tech')
    })

    it('category を明示指定すると source と別カテゴリになる', async () => {
      const res = await postJson('/', {
        url: 'https://example.com/a',
        source: 'Tech',
        category: 'あとで読む',
      })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.source).toBe('Tech')
      expect(body.category_name).toBe('あとで読む')
    })

    it('source も category も省略時は「未分類」カテゴリになる', async () => {
      const res = await postJson('/', { url: 'https://example.com/a' })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.category_name).toBe('未分類')
    })

    it('同名カテゴリは使い回される（get-or-create）', async () => {
      await postJson('/', { url: 'https://example.com/a', source: 'Tech' })
      await postJson('/', { url: 'https://example.com/b', source: 'Tech' })
      const categories = await (await stockCategoriesRouter.request('/')).json()
      expect(categories).toHaveLength(1)
      expect(categories[0].stock_count).toBe(2)
    })

    it('url 未指定は 400 で { error } を返す', async () => {
      const res = await postJson('/', {})
      expect(res.status).toBe(400)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })

    it('重複した url は 200 で既存ストックを返す（no-op、エラーにしない）', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', title: 'A', source: 'Tech' })).json()
      const res = await postJson('/', { url: 'https://example.com/a', title: 'B', source: 'News' })
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.id).toBe(created.id)
      // 既存の内容が維持される（新しい入力で上書きされない）
      expect(body.title).toBe('A')
      expect(body.category_name).toBe('Tech')
      const list = await (await stocksRouter.request('/')).json()
      expect(list).toHaveLength(1)
    })

    it('url の # 以降(フラグメント)は保存時に取り除かれる', async () => {
      const res = await postJson('/', { url: 'https://example.com/a#section2', source: 'Tech' })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.url).toBe('https://example.com/a')
    })

    it('# の有無だけが違う url は重複扱いになる', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await postJson('/', { url: 'https://example.com/a#section2', source: 'News' })
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.id).toBe(created.id)
    })
  })

  describe('GET /lookup', () => {
    it('既存の url があればストックを返す', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', title: 'A', source: 'Tech' })).json()
      const res = await stocksRouter.request(`/lookup?url=${encodeURIComponent('https://example.com/a')}`)
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.stock.id).toBe(created.id)
    })

    it('# 以降が違うだけの url でも既存として見つかる', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await stocksRouter.request(`/lookup?url=${encodeURIComponent('https://example.com/a#top')}`)
      const body = await res.json()
      expect(body.stock.id).toBe(created.id)
    })

    it('存在しない url は stock: null を返す', async () => {
      const res = await stocksRouter.request(`/lookup?url=${encodeURIComponent('https://example.com/not-found')}`)
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.stock).toBeNull()
    })

    it('url 未指定は 400 で { error } を返す', async () => {
      const res = await stocksRouter.request('/lookup')
      expect(res.status).toBe(400)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })
  })

  describe('PUT /:id', () => {
    it('タイトルとカテゴリを更新して 200 で返す', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', title: 'A', source: 'Tech' })).json()
      const res = await postJson(`/${created.id}`, { title: 'A2', category: 'あとで読む' }, 'PUT')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.title).toBe('A2')
      expect(body.category_name).toBe('あとで読む')
    })

    it('カテゴリ変更で旧カテゴリが空になったら自動削除される', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      await postJson(`/${created.id}`, { title: 'A', category: 'あとで読む' }, 'PUT')
      const categories = await (await stockCategoriesRouter.request('/')).json()
      expect(categories.map((c: { name: string }) => c.name)).toEqual(['あとで読む'])
    })

    it('存在しない id は 404 で { error } を返す', async () => {
      const res = await postJson('/999', { title: 'X', category: 'Y' }, 'PUT')
      expect(res.status).toBe(404)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })

    it('category 未指定は 400 で { error } を返す', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await postJson(`/${created.id}`, { title: 'A2' }, 'PUT')
      expect(res.status).toBe(400)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })

    it('category が空白のみは 400 で { error } を返す', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await postJson(`/${created.id}`, { title: 'A2', category: '   ' }, 'PUT')
      expect(res.status).toBe(400)
    })
  })

  describe('DELETE /:id', () => {
    it('204 を返し、ストックが消える', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await stocksRouter.request(`/${created.id}`, { method: 'DELETE' })
      expect(res.status).toBe(204)
      const list = await (await stocksRouter.request('/')).json()
      expect(list).toEqual([])
    })

    it('削除で空になったカテゴリが自動削除される', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      await stocksRouter.request(`/${created.id}`, { method: 'DELETE' })
      const categories = await (await stockCategoriesRouter.request('/')).json()
      expect(categories).toEqual([])
    })

    it('紐づく翻訳も削除される（CASCADE）', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      await stocksRouter.request(`/${created.id}/translation`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ segments: '{"version":1,"segments":[]}' }),
      })
      await stocksRouter.request(`/${created.id}`, { method: 'DELETE' })
      const res = await stocksRouter.request(`/${created.id}/translation`)
      expect(res.status).toBe(404)
    })
  })

  describe('PUT /:id/summary', () => {
    it('204 を返し、サマリーが保存される', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await postJson(`/${created.id}/summary`, { summary: '## 要約\nテスト' }, 'PUT')
      expect(res.status).toBe(204)
      const list = await (await stocksRouter.request('/')).json()
      expect(list[0].summary).toBe('## 要約\nテスト')
    })

    it('存在しない id は 404 を返す', async () => {
      const res = await postJson('/999/summary', { summary: 'x' }, 'PUT')
      expect(res.status).toBe(404)
    })
  })

  describe('翻訳', () => {
    it('GET は未保存なら 404 を返す', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const res = await stocksRouter.request(`/${created.id}/translation`)
      expect(res.status).toBe(404)
    })

    it('PUT で保存し GET で取得できる（再 PUT は上書き）', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      const putRes = await stocksRouter.request(`/${created.id}/translation`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ segments: '{"version":1,"segments":[{"i":0,"h":"x","t":"訳文1"}]}' }),
      })
      expect(putRes.status).toBe(204)

      const getRes = await stocksRouter.request(`/${created.id}/translation`)
      expect(getRes.status).toBe(200)
      const body = await getRes.json()
      expect(body.segments).toContain('訳文1')

      await stocksRouter.request(`/${created.id}/translation`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ segments: '{"version":1,"segments":[{"i":0,"h":"x","t":"訳文2"}]}' }),
      })
      const getRes2 = await stocksRouter.request(`/${created.id}/translation`)
      const body2 = await getRes2.json()
      expect(body2.segments).toContain('訳文2')

      const list = await (await stocksRouter.request('/')).json()
      expect(list[0].has_translation).toBe(true)
    })

    it('DELETE で削除できる', async () => {
      const created = await (await postJson('/', { url: 'https://example.com/a', source: 'Tech' })).json()
      await stocksRouter.request(`/${created.id}/translation`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ segments: '{"version":1,"segments":[]}' }),
      })
      const delRes = await stocksRouter.request(`/${created.id}/translation`, { method: 'DELETE' })
      expect(delRes.status).toBe(204)
      const getRes = await stocksRouter.request(`/${created.id}/translation`)
      expect(getRes.status).toBe(404)
    })
  })
})
