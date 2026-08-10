import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'

let db: Database.Database

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
})

afterEach(() => {
  db.close()
})

function columnNames(table: string): string[] {
  return (db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[]).map((c) => c.name)
}

describe('initSchema', () => {
  it('新規 DB に全テーブルと期待するカラムを作成する', () => {
    initSchema(db)

    expect(columnNames('groups')).toEqual(
      expect.arrayContaining(['id', 'name', 'created_at', 'is_secret', 'display_order'])
    )
    expect(columnNames('feeds')).toEqual(
      expect.arrayContaining(['id', 'url', 'title', 'favicon_url', 'group_id', 'last_fetched_at', 'display_order'])
    )
    expect(columnNames('articles')).toEqual(
      expect.arrayContaining(['id', 'feed_id', 'guid', 'title', 'link', 'is_read', 'read_at', 'liked_at'])
    )
    expect(columnNames('settings')).toEqual(expect.arrayContaining(['key', 'value']))
  })

  it('is_favorite カラムを作成しない（ストック機能に統合済み）', () => {
    initSchema(db)
    expect(columnNames('articles')).not.toContain('is_favorite')
  })

  it('AI 関連カラム（ai_summary / ai_translation / ai_audio_url）を作成しない', () => {
    initSchema(db)
    const cols = columnNames('articles')
    expect(cols).not.toContain('ai_summary')
    expect(cols).not.toContain('ai_translation')
    expect(cols).not.toContain('ai_audio_url')
  })

  it('2回実行しても冪等（エラーにならずデータも消えない）', () => {
    initSchema(db)
    db.prepare("INSERT INTO groups (name) VALUES ('G')").run()
    expect(() => initSchema(db)).not.toThrow()
    expect(db.prepare('SELECT COUNT(*) as c FROM groups').get()).toEqual({ c: 1 })
  })

  it('AI カラムが残っている旧 DB からカラムを除去する（データは保持）', () => {
    // 旧スキーマを再現: ai_summary 等を持つ articles テーブル
    db.exec(`
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT,
        favicon_url TEXT,
        group_id INTEGER REFERENCES groups(id) ON DELETE SET NULL,
        last_fetched_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
        guid TEXT NOT NULL,
        title TEXT,
        link TEXT,
        summary TEXT,
        content TEXT,
        published_at TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        ai_summary TEXT,
        ai_translation TEXT,
        ai_audio_url TEXT,
        UNIQUE(feed_id, guid)
      );
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO feeds (url) VALUES ('https://example.com/feed.xml');
      INSERT INTO articles (feed_id, guid, title, ai_summary) VALUES (1, 'g1', 'Hello', 'old summary');
    `)

    initSchema(db)

    const cols = columnNames('articles')
    expect(cols).not.toContain('ai_summary')
    expect(cols).not.toContain('ai_translation')
    expect(cols).not.toContain('ai_audio_url')
    expect(cols).not.toContain('is_favorite')
    expect(cols).toContain('read_at')
    expect(cols).toContain('liked_at')
    // 既存データは保持される
    expect(db.prepare('SELECT title FROM articles WHERE guid = ?').get('g1')).toEqual({ title: 'Hello' })
  })

  it('is_favorite カラムが残っている旧 DB から除去する（データは保持）', () => {
    db.exec(`
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT,
        favicon_url TEXT,
        group_id INTEGER REFERENCES groups(id) ON DELETE SET NULL,
        last_fetched_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
        guid TEXT NOT NULL,
        title TEXT,
        link TEXT,
        summary TEXT,
        content TEXT,
        published_at TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(feed_id, guid)
      );
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO feeds (url) VALUES ('https://example.com/feed.xml');
      INSERT INTO articles (feed_id, guid, title, is_favorite) VALUES (1, 'g1', 'Hello', 1);
    `)

    initSchema(db)

    const cols = columnNames('articles')
    expect(cols).not.toContain('is_favorite')
    expect(db.prepare('SELECT title FROM articles WHERE guid = ?').get('g1')).toEqual({ title: 'Hello' })
  })

  it('display_order は既存行の id 順で初期化される', () => {
    // display_order なしの旧 feeds テーブルを再現
    db.exec(`
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT,
        favicon_url TEXT,
        group_id INTEGER REFERENCES groups(id) ON DELETE SET NULL,
        last_fetched_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
        guid TEXT NOT NULL,
        title TEXT,
        link TEXT,
        summary TEXT,
        content TEXT,
        published_at TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(feed_id, guid)
      );
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO feeds (url) VALUES ('https://a.example.com'), ('https://b.example.com');
    `)

    initSchema(db)

    const rows = db.prepare('SELECT id, display_order FROM feeds ORDER BY id').all() as { id: number; display_order: number }[]
    expect(rows[0].display_order).toBe(rows[0].id)
    expect(rows[1].display_order).toBe(rows[1].id)
  })

  it('display_order 追加済みの場合、initSchema を再実行しても並び替え済みの値を上書きしない', () => {
    initSchema(db)
    db.prepare("INSERT INTO feeds (url) VALUES ('https://a.example.com'), ('https://b.example.com')").run()
    // reorder 相当の操作で id 順とは異なる並びに変更する
    const [a, b] = db.prepare('SELECT id FROM feeds ORDER BY id').all() as { id: number }[]
    db.prepare('UPDATE feeds SET display_order = ? WHERE id = ?').run(0, b.id)
    db.prepare('UPDATE feeds SET display_order = ? WHERE id = ?').run(1, a.id)

    initSchema(db)

    const rows = db.prepare('SELECT id, display_order FROM feeds ORDER BY display_order ASC').all() as {
      id: number
      display_order: number
    }[]
    expect(rows.map((r) => r.id)).toEqual([b.id, a.id])
  })
})
