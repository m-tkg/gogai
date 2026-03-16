import type Database from 'better-sqlite3'

export interface Group {
  id: number
  name: string
  created_at: string
}

export class GroupsService {
  constructor(private db: Database.Database) {}

  create(name: string): Group {
    const stmt = this.db.prepare('INSERT INTO groups (name) VALUES (?) RETURNING *')
    return stmt.get(name) as Group
  }

  findAll(): Group[] {
    return this.db.prepare('SELECT * FROM groups ORDER BY name').all() as Group[]
  }

  findById(id: number): Group | null {
    return (this.db.prepare('SELECT * FROM groups WHERE id = ?').get(id) as Group) ?? null
  }

  update(id: number, name: string): Group | null {
    const stmt = this.db.prepare('UPDATE groups SET name = ? WHERE id = ? RETURNING *')
    return (stmt.get(name, id) as Group) ?? null
  }

  remove(id: number): void {
    this.db.prepare('DELETE FROM groups WHERE id = ?').run(id)
  }
}
