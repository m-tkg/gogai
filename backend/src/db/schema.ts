import Database from 'better-sqlite3'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const DB_PATH = process.env.DB_PATH ?? path.join(__dirname, '../../data/rss.db')

let _db: Database.Database | null = null

export function getDb(): Database.Database {
  if (!_db) {
    _db = new Database(DB_PATH)
    _db.pragma('journal_mode = WAL')
    _db.pragma('foreign_keys = ON')
    initSchema(_db)
  }
  return _db
}

export function closeDb(): void {
  if (_db) {
    _db.close()
    _db = null
  }
}

// テスト専用: getDb() が返す DB を差し替える（ルートを in-memory DB でテストするための seam）
export function setDb(db: Database.Database | null): void {
  _db = db
}

export function initSchema(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS feeds (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      url TEXT NOT NULL UNIQUE,
      title TEXT,
      favicon_url TEXT,
      group_id INTEGER REFERENCES groups(id) ON DELETE SET NULL,
      last_fetched_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS articles (
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

    CREATE INDEX IF NOT EXISTS idx_articles_feed_id ON articles(feed_id);
    CREATE INDEX IF NOT EXISTS idx_articles_published_at ON articles(published_at DESC);

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  `)

  // カラムが存在しない場合のみ追加（既存 DB への移行）
  try {
    db.exec(`ALTER TABLE articles ADD COLUMN read_at TEXT`)
  } catch {
    // already exists — ignore
  }

  // AI 要約・翻訳・NotebookLM 音声機能の削除に伴い、残存カラムを除去する
  for (const col of ['ai_summary', 'ai_translation', 'ai_audio_url']) {
    try {
      db.exec(`ALTER TABLE articles DROP COLUMN ${col}`)
    } catch {
      // column doesn't exist — ignore
    }
  }

  // groups テーブルへの移行
  try {
    db.exec(`ALTER TABLE groups ADD COLUMN is_secret INTEGER NOT NULL DEFAULT 0`)
  } catch {
    // already exists — ignore
  }

  // feeds テーブルへの移行: 並び順カラムを追加
  try {
    db.exec(`ALTER TABLE feeds ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0`)
    // 既存フィードの display_order を id 順で初期化（挿入順を維持）
    db.exec(`UPDATE feeds SET display_order = id`)
  } catch {
    // already exists — ignore
  }

  // groups テーブルへの移行: 並び順カラムを追加
  try {
    db.exec(`ALTER TABLE groups ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0`)
    db.exec(`UPDATE groups SET display_order = id`)
  } catch {
    // already exists — ignore
  }

  // read_at カラム追加後にインデックスを作成
  try {
    db.exec(`CREATE INDEX IF NOT EXISTS idx_articles_read_at ON articles(read_at DESC)`)
  } catch {
    // ignore
  }

  // articles テーブルへの移行: お気に入りカラムを追加
  try {
    db.exec(`ALTER TABLE articles ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0`)
  } catch {
    // already exists — ignore
  }
}
