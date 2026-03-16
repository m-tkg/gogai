import axios from 'axios'

const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

export const api = axios.create({ baseURL: BASE_URL })

// Types
export interface Group {
  id: number
  name: string
  created_at: string
}

export interface Feed {
  id: number
  url: string
  title: string | null
  favicon_url: string | null
  group_id: number | null
  last_fetched_at: string | null
  created_at: string
}

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
  ai_summary: string | null
  ai_translation: string | null
}

// Groups API
export const groupsApi = {
  list: () => api.get<Group[]>('/api/groups').then(r => r.data),
  create: (name: string) => api.post<Group>('/api/groups', { name }).then(r => r.data),
  update: (id: number, name: string) => api.put<Group>(`/api/groups/${id}`, { name }).then(r => r.data),
  remove: (id: number) => api.delete(`/api/groups/${id}`),
}

// Feeds API
export const feedsApi = {
  list: () => api.get<Feed[]>('/api/feeds').then(r => r.data),
  create: (url: string, groupId?: number) => api.post<Feed>('/api/feeds', { url, groupId }).then(r => r.data),
  update: (id: number, data: { title?: string; groupId?: number | null }) => api.put<Feed>(`/api/feeds/${id}`, data).then(r => r.data),
  remove: (id: number) => api.delete(`/api/feeds/${id}`),
  refresh: (id: number) => api.post(`/api/feeds/${id}/refresh`).then(r => r.data),
}

// Articles API
export const articlesApi = {
  list: (params: { feedId?: number; groupId?: number; unreadOnly?: boolean; limit?: number; offset?: number }) =>
    api.get<Article[]>('/api/articles', { params }).then(r => r.data),
  get: (id: number) => api.get<Article>(`/api/articles/${id}`).then(r => r.data),
  markAsRead: (id: number) => api.post(`/api/articles/${id}/read`),
  markAsUnread: (id: number) => api.post(`/api/articles/${id}/unread`),
  claude: (id: number, action: 'summarize' | 'translate', force?: boolean) =>
    api.post<{ output: string; cached: boolean }>(`/api/articles/${id}/claude`, { action, force }).then(r => r.data),
}
