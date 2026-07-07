// アプリ全体で共有する設定値。
// retention_days のデフォルトと上限は同値（180日）だが意味が異なるため別名で定義する。
export const RETENTION_DAYS_DEFAULT = 180
export const RETENTION_DAYS_MIN = 3
export const RETENTION_DAYS_MAX = 180

// GET /api/articles の limit クエリの上限
export const MAX_ARTICLES_LIMIT = 1000
