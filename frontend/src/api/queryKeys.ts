import type { QueryClient } from '@tanstack/react-query'
import type { SortBy } from './client'

export interface ArticleListFilter {
  feedId: number | null
  groupId: number | null
  unreadOnly: boolean
  sortBy: SortBy
  showSecretGroups: boolean
}

// TanStack Query のキャッシュキーを一元管理する。
// 文字列リテラルを直接書かず、必ずここを経由すること。
export const queryKeys = {
  groups: ['groups'] as const,
  feeds: ['feeds'] as const,
  articles: ['articles'] as const,
  articleList: (filter: ArticleListFilter) => ['articles', filter] as const,
  settings: ['settings'] as const,
  updateCheck: ['update-check'] as const,
}

export function invalidateArticles(qc: QueryClient): void {
  qc.invalidateQueries({ queryKey: queryKeys.articles })
}

export function invalidateFeeds(qc: QueryClient): void {
  qc.invalidateQueries({ queryKey: queryKeys.feeds })
}

export function invalidateGroups(qc: QueryClient): void {
  qc.invalidateQueries({ queryKey: queryKeys.groups })
}

// フィード操作（追加・削除・更新）後の定番: 一覧と記事の両方を更新する
export function invalidateFeedsAndArticles(qc: QueryClient): void {
  qc.invalidateQueries({ queryKey: queryKeys.feeds })
  qc.invalidateQueries({ queryKey: queryKeys.articles })
}
