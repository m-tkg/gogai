import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useFeedMutations } from './useFeedMutations'
import { useGroupMutations } from './useGroupMutations'

vi.mock('../api/client', () => ({
  feedsApi: {
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    refresh: vi.fn(),
    refreshAll: vi.fn(),
    reorder: vi.fn(),
  },
  groupsApi: {
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    refresh: vi.fn(),
    reorder: vi.fn(),
  },
}))

import { feedsApi, groupsApi } from '../api/client'

let qc: QueryClient
let invalidateSpy: ReturnType<typeof vi.spyOn>

function wrapper({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

beforeEach(() => {
  vi.clearAllMocks()
  qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  invalidateSpy = vi.spyOn(qc, 'invalidateQueries')
})

describe('useFeedMutations', () => {
  it('addFeed は feedsApi.create を呼び、feeds と articles を無効化する', async () => {
    vi.mocked(feedsApi.create).mockResolvedValue({ id: 1 } as never)
    const { result } = renderHook(() => useFeedMutations(), { wrapper })

    result.current.addFeed.mutate({ url: 'https://example.com', groupId: 2 })

    await waitFor(() => expect(result.current.addFeed.isSuccess).toBe(true))
    expect(feedsApi.create).toHaveBeenCalledWith('https://example.com', 2)
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['feeds'] })
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['articles'] })
  })

  it('removeFeed は feeds のみ無効化する', async () => {
    vi.mocked(feedsApi.remove).mockResolvedValue({} as never)
    const { result } = renderHook(() => useFeedMutations(), { wrapper })

    result.current.removeFeed.mutate(5)

    await waitFor(() => expect(result.current.removeFeed.isSuccess).toBe(true))
    expect(feedsApi.remove).toHaveBeenCalledWith(5)
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['feeds'] })
    expect(invalidateSpy).not.toHaveBeenCalledWith({ queryKey: ['articles'] })
  })

  it('updateFeed / refreshFeed / refreshAllFeeds は feeds と articles を無効化する', async () => {
    vi.mocked(feedsApi.update).mockResolvedValue({} as never)
    vi.mocked(feedsApi.refresh).mockResolvedValue({} as never)
    vi.mocked(feedsApi.refreshAll).mockResolvedValue({ refreshed: 1, failed: 0 })
    const { result } = renderHook(() => useFeedMutations(), { wrapper })

    result.current.updateFeed.mutate({ id: 1, data: { title: 'X' } })
    await waitFor(() => expect(result.current.updateFeed.isSuccess).toBe(true))
    expect(feedsApi.update).toHaveBeenCalledWith(1, { title: 'X' })

    result.current.refreshFeed.mutate(1)
    await waitFor(() => expect(result.current.refreshFeed.isSuccess).toBe(true))

    result.current.refreshAllFeeds.mutate()
    await waitFor(() => expect(result.current.refreshAllFeeds.isSuccess).toBe(true))

    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['articles'] })
  })

  it('reorderFeeds は feedsApi.reorder を呼ぶ', async () => {
    vi.mocked(feedsApi.reorder).mockResolvedValue({} as never)
    const { result } = renderHook(() => useFeedMutations(), { wrapper })

    result.current.reorderFeeds.mutate([3, 1, 2])
    await waitFor(() => expect(result.current.reorderFeeds.isSuccess).toBe(true))
    expect(feedsApi.reorder).toHaveBeenCalledWith([3, 1, 2])
  })
})

describe('useGroupMutations', () => {
  it('addGroup は groupsApi.create を呼び groups を無効化する', async () => {
    vi.mocked(groupsApi.create).mockResolvedValue({ id: 1 } as never)
    const { result } = renderHook(() => useGroupMutations(), { wrapper })

    result.current.addGroup.mutate('News')
    await waitFor(() => expect(result.current.addGroup.isSuccess).toBe(true))
    expect(groupsApi.create).toHaveBeenCalledWith('News')
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['groups'] })
  })

  it('toggleGroupSecret は groupsApi.update に is_secret を渡す', async () => {
    vi.mocked(groupsApi.update).mockResolvedValue({} as never)
    const { result } = renderHook(() => useGroupMutations(), { wrapper })

    result.current.toggleGroupSecret.mutate({ id: 1, name: 'Tech', isSecret: 1 })
    await waitFor(() => expect(result.current.toggleGroupSecret.isSuccess).toBe(true))
    expect(groupsApi.update).toHaveBeenCalledWith(1, 'Tech', 1)
  })

  it('refreshGroup は feeds と articles を無効化する', async () => {
    vi.mocked(groupsApi.refresh).mockResolvedValue({ refreshed: 1, failed: 0 })
    const { result } = renderHook(() => useGroupMutations(), { wrapper })

    result.current.refreshGroup.mutate(1)
    await waitFor(() => expect(result.current.refreshGroup.isSuccess).toBe(true))
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['feeds'] })
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['articles'] })
  })

  it('removeGroup / reorderGroups は groups を無効化する', async () => {
    vi.mocked(groupsApi.remove).mockResolvedValue({} as never)
    vi.mocked(groupsApi.reorder).mockResolvedValue({} as never)
    const { result } = renderHook(() => useGroupMutations(), { wrapper })

    result.current.removeGroup.mutate(1)
    await waitFor(() => expect(result.current.removeGroup.isSuccess).toBe(true))

    result.current.reorderGroups.mutate([2, 1])
    await waitFor(() => expect(result.current.reorderGroups.isSuccess).toBe(true))
    expect(groupsApi.reorder).toHaveBeenCalledWith([2, 1])
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['groups'] })
  })
})
