import { describe, it, expect } from 'vitest'
import settingsRouter from '../../routes/settings.js'
import { useTestDb } from '../helpers/db.js'
import { jsonRequest } from '../helpers/http.js'

useTestDb()

function putJson(body: unknown) {
  return jsonRequest(settingsRouter, '/', body, 'PUT')
}

describe('settings ルート（HTTP 契約）', () => {
  describe('GET /', () => {
    it('未設定ならデフォルト retention_days: 180 を返す', async () => {
      const res = await settingsRouter.request('/')
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual({ retention_days: 180 })
    })

    it('設定済みの値を返す', async () => {
      await putJson({ retention_days: 30 })
      const res = await settingsRouter.request('/')
      expect(await res.json()).toEqual({ retention_days: 30 })
    })
  })

  describe('PUT /', () => {
    it('有効な値は 200 で { retention_days } を返す', async () => {
      const res = await putJson({ retention_days: 90 })
      expect(res.status).toBe(200)
      expect(await res.json()).toEqual({ retention_days: 90 })
    })

    it('下限 3・上限 180 は許可される', async () => {
      expect((await putJson({ retention_days: 3 })).status).toBe(200)
      expect((await putJson({ retention_days: 180 })).status).toBe(200)
    })

    it('範囲外は 400 で { error } を返す', async () => {
      for (const days of [2, 181, 0, -1]) {
        const res = await putJson({ retention_days: days })
        expect(res.status).toBe(400)
        expect((await res.json()).error).toBeTypeOf('string')
      }
    })

    it('整数以外は 400 を返す', async () => {
      for (const days of [1.5, 'abc', null, undefined]) {
        const res = await putJson({ retention_days: days })
        expect(res.status).toBe(400)
      }
    })
  })
})
