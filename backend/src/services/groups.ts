import type Database from 'better-sqlite3'

export interface Group {
  id: number
  name: string
  is_secret: number
  created_at: string
}

export class GroupsService {
  constructor(private db: Database.Database) {}

  create(name: string, isSecret = 0): Group {
    const stmt = this.db.prepare('INSERT INTO groups (name, is_secret) VALUES (?, ?) RETURNING *')
    return stmt.get(name, isSecret) as Group
  }

  findAll(): Group[] {
    return this.db.prepare('SELECT * FROM groups ORDER BY name').all() as Group[]
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
