import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { SettingsService } from '../services/settings.js'

let db: Database.Database
let service: SettingsService

beforeEach(() => {
  db = new Database(':memory:')
  initSchema(db)
  service = new SettingsService(db)
})

afterEach(() => db.close())

describe('SettingsService', () => {
  it('存在しないキーはデフォルト値を返す', () => {
    expect(service.get('retention_days', 180)).toBe(180)
  })

  it('値を保存して取得できる', () => {
    service.set('retention_days', 30)
    expect(service.get('retention_days', 180)).toBe(30)
  })

  it('値を上書きできる', () => {
    service.set('retention_days', 30)
    service.set('retention_days', 60)
    expect(service.get('retention_days', 180)).toBe(60)
  })

  it('全設定をオブジェクトとして取得できる', () => {
    service.set('retention_days', 90)
    expect(service.getAll()).toEqual({ retention_days: 90 })
  })
})
