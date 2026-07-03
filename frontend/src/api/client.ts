import axios from 'axios'
import type { Group, Feed, Article, RefreshResult, Settings, UpdateCheck, SortBy } from './types'

const BASE_URL = import.meta.env.VITE_API_URL ?? ''

export const api = axios.create({ baseURL: BASE_URL })

// 型は types.ts に定義。既存 import 互換のため再エクスポートする。
export type { Group, Feed, Article, RefreshResult, Settings, UpdateCheck, SortBy } from './types'

// Groups API
export const groupsApi = {
  list: () => api.get<Group[]>('/api/groups').then(r => r.data),
  create: (name: string, isSecret?: number) => api.post<Group>('/api/groups', { name, is_secret: isSecret ?? 0 }).then(r => r.data),
  update: (id: number, name: string, isSecret?: number) => api.put<Group>(`/api/groups/${id}`, { name, ...(isSecret !== undefined && { is_secret: isSecret }) }).then(r => r.data),
  remove: (id: number) => api.delete(`/api/groups/${id}`),
  refresh: (id: number) => api.post<RefreshResult>(`/api/groups/${id}/refresh`).then(r => r.data),
  reorder: (ids: number[]) => api.patch('/api/groups/reorder', { ids }),
}

// Feeds API
export const feedsApi = {
  list: () => api.get<Feed[]>('/api/feeds').then(r => r.data),
  create: (url: string, groupId?: number) => api.post<Feed>('/api/feeds', { url, groupId }).then(r => r.data),
  update: (id: number, data: { url?: string; title?: string; groupId?: number | null }) => api.put<Feed>(`/api/feeds/${id}`, data).then(r => r.data),
  remove: (id: number) => api.delete(`/api/feeds/${id}`),
  refresh: (id: number) => api.post(`/api/feeds/${id}/refresh`).then(r => r.data),
  refreshAll: () => api.post<RefreshResult>('/api/feeds/refresh-all').then(r => r.data),
  reorder: (ids: number[]) => api.patch('/api/feeds/reorder', { ids }),
}

// Settings API
export const settingsApi = {
  get: () => api.get<Settings>('/api/settings').then(r => r.data),
  update: (data: Partial<Settings>) => api.put<Settings>('/api/settings', data).then(r => r.data),
}

// Admin API
export const adminApi = {
  updateCheck: () => api.get<UpdateCheck>('/api/admin/update-check').then(r => r.data),
  restart: () => api.post<{ output: string }>('/api/admin/restart').then(r => r.data),
}

// Articles API
export const articlesApi = {
  list: (params: { feedId?: number; groupId?: number; unreadOnly?: boolean; sortBy?: SortBy; limit?: number; offset?: number; includeSecret?: boolean }) =>
    api.get<Article[]>('/api/articles', { params }).then(r => r.data),
  get: (id: number) => api.get<Article>(`/api/articles/${id}`).then(r => r.data),
  markAsRead: (id: number) => api.post(`/api/articles/${id}/read`),
  markAsUnread: (id: number) => api.post(`/api/articles/${id}/unread`),
}
