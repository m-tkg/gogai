import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useFeedMutations } from './useFeedMutations'

vi.mock('../api/client', () => ({
  feedsApi: {
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    refresh: vi.fn(),
    refreshAll: vi.fn(),
    reorder: vi.fn(),
  },
}))

import { feedsApi } from '../api/client'

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
