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

// ---------------------------------------------------------------------------
// マイグレーション
//
// 各エントリは冪等（何度実行しても安全）であること。
// 新しい変更はリストの末尾に追加する。マイグレーション履歴はこのリストが唯一の記録。
// ---------------------------------------------------------------------------

function addColumn(db: Database.Database, table: string, columnDef: string): void {
  try {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${columnDef}`)
  } catch {
    // already exists — ignore
  }
}

function dropColumn(db: Database.Database, table: string, column: string): void {
  try {
    db.exec(`ALTER TABLE ${table} DROP COLUMN ${column}`)
  } catch {
    // column doesn't exist — ignore
  }
}

interface Migration {
  name: string
  up: (db: Database.Database) => void
}

const MIGRATIONS: Migration[] = [
  {
    name: 'create-base-tables',
    up: (db) => {
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
    },
  },
  {
    name: 'articles-add-read-at',
    up: (db) => {
      addColumn(db, 'articles', 'read_at TEXT')
      db.exec(`CREATE INDEX IF NOT EXISTS idx_articles_read_at ON articles(read_at DESC)`)
    },
  },
  {
    name: 'groups-add-is-secret',
    up: (db) => {
      addColumn(db, 'groups', 'is_secret INTEGER NOT NULL DEFAULT 0')
    },
  },
  {
    name: 'feeds-add-display-order',
    up: (db) => {
      try {
        db.exec(`ALTER TABLE feeds ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0`)
        // 既存フィードの display_order を id 順で初期化（挿入順を維持）
        db.exec(`UPDATE feeds SET display_order = id`)
      } catch {
        // already exists — ignore
      }
    },
  },
  {
    name: 'groups-add-display-order',
    up: (db) => {
      try {
        db.exec(`ALTER TABLE groups ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0`)
        db.exec(`UPDATE groups SET display_order = id`)
      } catch {
        // already exists — ignore
      }
    },
  },
  {
    name: 'articles-add-is-favorite',
    up: (db) => {
      addColumn(db, 'articles', 'is_favorite INTEGER NOT NULL DEFAULT 0')
    },
  },
  {
    name: 'articles-drop-ai-columns',
    up: (db) => {
      // AI 要約・翻訳・NotebookLM 音声機能の削除に伴い、残存カラムを除去する
      for (const col of ['ai_summary', 'ai_translation', 'ai_audio_url']) {
        dropColumn(db, 'articles', col)
      }
    },
  },
  {
    name: 'create-stock-tables',
    up: (db) => {
      db.exec(`
        CREATE TABLE IF NOT EXISTS stock_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          display_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS stocks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT NOT NULL UNIQUE,
          title TEXT,
          source TEXT NOT NULL DEFAULT '',
          category_id INTEGER NOT NULL REFERENCES stock_categories(id),
          summary TEXT,
          stocked_at TEXT NOT NULL DEFAULT (datetime('now')),
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_stocks_category_id ON stocks(category_id);
        CREATE INDEX IF NOT EXISTS idx_stocks_stocked_at ON stocks(stocked_at DESC);

        CREATE TABLE IF NOT EXISTS stock_translations (
          stock_id INTEGER PRIMARY KEY REFERENCES stocks(id) ON DELETE CASCADE,
          segments TEXT NOT NULL,
          translated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      `)
    },
  },
  {
    name: 'articles-drop-is-favorite',
    up: (db) => {
      // お気に入り機能をストック機能に統合したため削除する
      dropColumn(db, 'articles', 'is_favorite')
    },
  },
]

export function initSchema(db: Database.Database): void {
  for (const migration of MIGRATIONS) {
    migration.up(db)
  }
}
