import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type Database from 'better-sqlite3'
import { createTestDb } from '../helpers/db.js'
import { nextDisplayOrder } from '../../services/shared/display-order.js'

let db: Database.Database

beforeEach(() => {
  db = createTestDb()
})

afterEach(() => db.close())

describe('nextDisplayOrder', () => {
  it('行がなければ 0 を返す', () => {
    expect(nextDisplayOrder(db, 'groups')).toBe(0)
  })

  it('既存の最大 display_order + 1 を返す', () => {
    db.prepare("INSERT INTO groups (name, display_order) VALUES ('A', 0), ('B', 3)").run()
    expect(nextDisplayOrder(db, 'groups')).toBe(4)
  })

  it('whereClause と params で絞り込んだ範囲だけを見る', () => {
    db.prepare("INSERT INTO groups (id, name) VALUES (1, 'G')").run()
    db.prepare(
      "INSERT INTO feeds (url, group_id, display_order) VALUES ('https://a', 1, 0), ('https://b', 1, 1), ('https://c', NULL, 5)"
    ).run()

    expect(nextDisplayOrder(db, 'feeds', 'group_id IS ?', [1])).toBe(2)
    expect(nextDisplayOrder(db, 'feeds', 'group_id IS ?', [null])).toBe(6)
  })
})
