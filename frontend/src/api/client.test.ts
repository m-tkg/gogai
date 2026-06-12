import { describe, it, expect, vi, beforeEach } from 'vitest'

const http = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
  patch: vi.fn(),
}))

vi.mock('axios', () => ({
  default: { create: () => http },
}))

import { groupsApi, feedsApi, articlesApi, settingsApi, adminApi } from './client'

beforeEach(() => {
  vi.clearAllMocks()
})

describe('api client', () => {
  it('groupsApi.list は GET /api/groups の data を返す', async () => {
    http.get.mockResolvedValue({ data: [{ id: 1, name: 'Tech' }] })
    const result = await groupsApi.list()
    expect(http.get).toHaveBeenCalledWith('/api/groups')
    expect(result).toEqual([{ id: 1, name: 'Tech' }])
  })

  it('groupsApi.create は name と is_secret を POST する', async () => {
    http.post.mockResolvedValue({ data: { id: 1 } })
    await groupsApi.create('Tech', 1)
    expect(http.post).toHaveBeenCalledWith('/api/groups', { name: 'Tech', is_secret: 1 })
  })

  it('feedsApi.create は url と groupId を POST する', async () => {
    http.post.mockResolvedValue({ data: { id: 1 } })
    await feedsApi.create('https://example.com', 2)
    expect(http.post).toHaveBeenCalledWith('/api/feeds', { url: 'https://example.com', groupId: 2 })
  })

  it('feedsApi.reorder は PATCH /api/feeds/reorder に ids を送る', async () => {
    http.patch.mockResolvedValue({})
    await feedsApi.reorder([3, 1, 2])
    expect(http.patch).toHaveBeenCalledWith('/api/feeds/reorder', { ids: [3, 1, 2] })
  })

  it('articlesApi.list はフィルターを params として渡す', async () => {
    http.get.mockResolvedValue({ data: [] })
    await articlesApi.list({ feedId: 1, unreadOnly: true, limit: 100, offset: 0 })
    expect(http.get).toHaveBeenCalledWith('/api/articles', {
      params: { feedId: 1, unreadOnly: true, limit: 100, offset: 0 },
    })
  })

  it('articlesApi.markAsRead は POST /api/articles/:id/read を呼ぶ', async () => {
    http.post.mockResolvedValue({})
    await articlesApi.markAsRead(5)
    expect(http.post).toHaveBeenCalledWith('/api/articles/5/read')
  })

  it('settingsApi.update は PUT /api/settings に部分更新を送る', async () => {
    http.put.mockResolvedValue({ data: { retention_days: 30 } })
    const result = await settingsApi.update({ retention_days: 30 })
    expect(http.put).toHaveBeenCalledWith('/api/settings', { retention_days: 30 })
    expect(result).toEqual({ retention_days: 30 })
  })

  it('adminApi.restart は POST /api/admin/restart を呼ぶ', async () => {
    http.post.mockResolvedValue({ data: { output: 'ok' } })
    const result = await adminApi.restart()
    expect(result).toEqual({ output: 'ok' })
  })
})
