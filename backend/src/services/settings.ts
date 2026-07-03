import type Database from 'better-sqlite3'

export class SettingsService {
  constructor(private db: Database.Database) {}

  get(key: string, defaultValue: number): number {
    const row = this.db.prepare('SELECT value FROM settings WHERE key = ?').get(key) as { value: string } | undefined
    return row ? Number(row.value) : defaultValue
  }

  set(key: string, value: number): void {
    this.db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)').run(key, String(value))
  }

  getAll(): Record<string, number> {
    const rows = this.db.prepare('SELECT key, value FROM settings').all() as { key: string; value: string }[]
    return Object.fromEntries(rows.map(r => [r.key, Number(r.value)]))
  }
}
