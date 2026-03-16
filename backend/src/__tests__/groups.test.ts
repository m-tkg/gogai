import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { GroupsService } from '../services/groups.js'

let db: Database.Database
let service: GroupsService

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
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
})
