import { beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema, setDb, closeDb } from '../../db/schema.js'

/// サービス層のテスト用: foreign_keys 有効・スキーマ初期化済みの in-memory DB を作る。
/// ルートテストのように getDb() の差し替えが不要な場合はこちらを使う。
export function createTestDb(): Database.Database {
  const db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  return db
}

/// ルートテスト用: 各 it() の前に in-memory DB を作って getDb() を差し替え、
/// 後で閉じる（beforeEach/afterEach を内部で登録する）。
/// 呼び出し側は `const getTestDb = useTestDb()` とし、db に直接触れたい箇所だけ
/// `getTestDb()` で現在の DB インスタンスを参照する。
export function useTestDb(): () => Database.Database {
  let db: Database.Database
  beforeEach(() => {
    db = createTestDb()
    setDb(db)
  })
  afterEach(() => {
    closeDb()
  })
  return () => db
}
