import type Database from 'better-sqlite3'
import { reorderByDisplayOrder } from './shared/reorder.js'
import { nextDisplayOrder } from './shared/display-order.js'

export interface Group {
  id: number
  name: string
  is_secret: number
  created_at: string
  display_order: number
}

export class GroupsService {
  constructor(private db: Database.Database) {}

  create(name: string, isSecret = 0): Group {
    const displayOrder = nextDisplayOrder(this.db, 'groups')
    const stmt = this.db.prepare('INSERT INTO groups (name, is_secret, display_order) VALUES (?, ?, ?) RETURNING *')
    return stmt.get(name, isSecret, displayOrder) as Group
  }

  findAll(): Group[] {
    return this.db.prepare('SELECT * FROM groups ORDER BY display_order ASC, id ASC').all() as Group[]
  }

  reorder(ids: number[]): void {
    reorderByDisplayOrder(this.db, 'groups', ids)
  }

  findById(id: number): Group | null {
    return (this.db.prepare('SELECT * FROM groups WHERE id = ?').get(id) as Group) ?? null
  }

  update(id: number, name: string, isSecret?: number): Group | null {
    const current = this.findById(id)
    if (!current) return null
    const stmt = this.db.prepare('UPDATE groups SET name = ?, is_secret = ? WHERE id = ? RETURNING *')
    return (stmt.get(name, isSecret ?? current.is_secret, id) as Group) ?? null
  }

  remove(id: number): void {
    this.db.prepare('DELETE FROM groups WHERE id = ?').run(id)
  }
}
