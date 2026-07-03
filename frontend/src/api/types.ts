// バックエンド API のワイヤ型。
// is_read / is_secret は SQLite の実態に合わせて number(0|1) のまま扱う。

export interface Group {
  id: number
  name: string
  is_secret: number
  created_at: string
  display_order: number
}

export interface Feed {
  id: number
  url: string
  title: string | null
  favicon_url: string | null
  group_id: number | null
  last_fetched_at: string | null
  created_at: string
  display_order: number
}

export type SortBy = 'published_at' | 'read_at'

export interface Article {
  id: number
  feed_id: number
  guid: string
  title: string | null
  link: string | null
  summary: string | null
  content: string | null
  published_at: string | null
  is_read: number
  created_at: string
  read_at: string | null
}

export interface RefreshResult {
  refreshed: number
  failed: number
}

export interface Settings {
  retention_days: number
}

export interface UpdateCheck {
  local: string
  remote: string
  hasUpdate: boolean
}
