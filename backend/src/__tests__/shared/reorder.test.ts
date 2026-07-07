import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type Database from 'better-sqlite3'
import { createTestDb } from '../helpers/db.js'
import { reorderByDisplayOrder } from '../../services/shared/reorder.js'

let db: Database.Database

beforeEach(() => {
  db = createTestDb()
  db.prepare("INSERT INTO groups (id, name, display_order) VALUES (1, 'A', 0), (2, 'B', 1), (3, 'C', 2)").run()
})

afterEach(() => db.close())

describe('reorderByDisplayOrder', () => {
  it('渡した順に display_order を 0 始まりで振り直す', () => {
    reorderByDisplayOrder(db, 'groups', [3, 1, 2])

    const rows = db.prepare('SELECT id, display_order FROM groups ORDER BY display_order ASC').all() as {
      id: number
      display_order: number
    }[]
    expect(rows.map((r) => r.id)).toEqual([3, 1, 2])
    expect(rows.map((r) => r.display_order)).toEqual([0, 1, 2])
  })

  it('空配列なら何もしない', () => {
    reorderByDisplayOrder(db, 'groups', [])

    const rows = db.prepare('SELECT id, display_order FROM groups ORDER BY display_order ASC').all() as {
      id: number
      display_order: number
    }[]
    expect(rows.map((r) => r.id)).toEqual([1, 2, 3])
  })
})
