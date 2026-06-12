import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema, setDb, closeDb } from '../../db/schema.js'
import groupsRouter from '../../routes/groups.js'

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
  return groupsRouter.request(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

describe('groups ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('グループがなければ空配列を返す', async () => {
      const res = await groupsRouter.request('/')
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual([])
    })

    it('作成済みグループを配列で返す', async () => {
      await postJson('/', { name: 'Tech' })
      const res = await groupsRouter.request('/')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body).toHaveLength(1)
      expect(body[0].name).toBe('Tech')
    })
  })

  describe('POST /', () => {
    it('201 で作成したグループを返す', async () => {
      const res = await postJson('/', { name: 'Tech' })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.id).toBeTypeOf('number')
      expect(body.name).toBe('Tech')
      expect(body.is_secret).toBe(0)
    })

    it('is_secret = 1 を指定して作成できる', async () => {
      const res = await postJson('/', { name: 'Secret', is_secret: 1 })
      expect(res.status).toBe(201)
      const body = await res.json()
      expect(body.is_secret).toBe(1)
    })

    it('name 未指定は 400 で { error } を返す', async () => {
      const res = await postJson('/', {})
      expect(res.status).toBe(400)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })

    it('name が空白のみは 400 を返す', async () => {
      const res = await postJson('/', { name: '   ' })
      expect(res.status).toBe(400)
    })

    it('重複した name は 409 で { error } を返す', async () => {
      await postJson('/', { name: 'Tech' })
      const res = await postJson('/', { name: 'Tech' })
      expect(res.status).toBe(409)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })
  })

  describe('PUT /:id', () => {
    it('名前を更新して 200 で返す', async () => {
      const created = await (await postJson('/', { name: 'Tech' })).json()
      const res = await postJson(`/${created.id}`, { name: 'Technology' }, 'PUT')
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.name).toBe('Technology')
    })

    it('存在しない id は 404 で { error } を返す', async () => {
      const res = await postJson('/999', { name: 'X' }, 'PUT')
      expect(res.status).toBe(404)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })
  })

  describe('DELETE /:id', () => {
    it('204 を返し、グループが消える', async () => {
      const created = await (await postJson('/', { name: 'Tech' })).json()
      const res = await groupsRouter.request(`/${created.id}`, { method: 'DELETE' })
      expect(res.status).toBe(204)
      const list = await (await groupsRouter.request('/')).json()
      expect(list).toEqual([])
    })
  })

  describe('PATCH /reorder', () => {
    it('ids の順に並び替えて 204 を返す', async () => {
      const a = await (await postJson('/', { name: 'A' })).json()
      const b = await (await postJson('/', { name: 'B' })).json()
      const res = await postJson('/reorder', { ids: [b.id, a.id] }, 'PATCH')
      expect(res.status).toBe(204)
      const list = await (await groupsRouter.request('/')).json()
      expect(list.map((g: { name: string }) => g.name)).toEqual(['B', 'A'])
    })

    it('ids が整数配列でなければ 400 で { error } を返す', async () => {
      const res = await postJson('/reorder', { ids: ['x'] }, 'PATCH')
      expect(res.status).toBe(400)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })
  })

  describe('POST /:id/refresh', () => {
    it('存在しないグループは 404 で { error } を返す', async () => {
      const res = await groupsRouter.request('/999/refresh', { method: 'POST' })
      expect(res.status).toBe(404)
      const body = await res.json()
      expect(body.error).toBeTypeOf('string')
    })

    it('フィードのないグループは refreshed: 0 を返す', async () => {
      const created = await (await postJson('/', { name: 'Tech' })).json()
      const res = await groupsRouter.request(`/${created.id}/refresh`, { method: 'POST' })
      expect(res.status).toBe(200)
      const body = await res.json()
      expect(body.refreshed).toBe(0)
    })
  })
})
