import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type Database from 'better-sqlite3'
import { GroupsService } from '../services/groups.js'
import { createTestDb } from './helpers/db.js'

let db: Database.Database
let service: GroupsService

beforeEach(() => {
  db = createTestDb()
  service = new GroupsService(db)
})

afterEach(() => {
  db.close()
})

describe('GroupsService', () => {
  it('グループを作成できる', () => {
    const group = service.create('Tech')
    expect(group.id).toBeTypeOf('number')
    expect(group.name).toBe('Tech')
  })

  it('全グループを取得できる', () => {
    service.create('Tech')
    service.create('News')
    const groups = service.findAll()
    expect(groups).toHaveLength(2)
  })

  it('IDでグループを取得できる', () => {
    const created = service.create('Tech')
    const found = service.findById(created.id)
    expect(found?.name).toBe('Tech')
  })

  it('存在しないIDはnullを返す', () => {
    expect(service.findById(999)).toBeNull()
  })

  it('グループ名を更新できる', () => {
    const group = service.create('Tech')
    const updated = service.update(group.id, 'Technology')
    expect(updated?.name).toBe('Technology')
  })

  it('グループを削除できる', () => {
    const group = service.create('Tech')
    service.remove(group.id)
    expect(service.findById(group.id)).toBeNull()
  })

  it('同名グループは作成できない', () => {
    service.create('Tech')
    expect(() => service.create('Tech')).toThrow()
  })

  describe('is_secret フラグ', () => {
    it('作成時はデフォルトで is_secret が 0 になる', () => {
      const group = service.create('Tech')
      expect(group.is_secret).toBe(0)
    })

    it('is_secret = 1 でグループを作成できる', () => {
      const group = service.create('Secret Group', 1)
      expect(group.is_secret).toBe(1)
    })

    it('update で is_secret を変更できる', () => {
      const group = service.create('Tech')
      const updated = service.update(group.id, 'Tech', 1)
      expect(updated?.is_secret).toBe(1)
    })

    it('update で is_secret を 0 に戻せる', () => {
      const group = service.create('Secret', 1)
      const updated = service.update(group.id, 'Secret', 0)
      expect(updated?.is_secret).toBe(0)
    })

    it('findAll で is_secret フィールドが含まれる', () => {
      service.create('Public')
      service.create('Secret', 1)
      const groups = service.findAll()
      expect(groups[0].is_secret).toBeDefined()
      expect(groups[1].is_secret).toBeDefined()
    })
  })

  describe('並び替え', () => {
    it('新規グループは末尾に追加される', () => {
      const g1 = service.create('A')
      const g2 = service.create('B')
      expect(g2.display_order).toBeGreaterThan(g1.display_order)
    })

    it('reorderでグループの並び順を変更できる', () => {
      const g1 = service.create('A')
      const g2 = service.create('B')
      const g3 = service.create('C')

      service.reorder([g3.id, g1.id, g2.id])

      const groups = service.findAll()
      const ids = groups.map(g => g.id)
      expect(ids.indexOf(g3.id)).toBeLessThan(ids.indexOf(g1.id))
      expect(ids.indexOf(g1.id)).toBeLessThan(ids.indexOf(g2.id))
    })
  })
})
