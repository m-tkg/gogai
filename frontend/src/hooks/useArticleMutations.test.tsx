import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useArticleMutations } from './useArticleMutations'

vi.mock('../api/client', () => ({
  articlesApi: {
    markAsRead: vi.fn(),
    markAsUnread: vi.fn(),
  },
  feedsApi: {
    refresh: vi.fn(),
  },
}))

import { articlesApi, feedsApi } from '../api/client'

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

describe('useArticleMutations', () => {
  it('refresh は feedId が指定されていれば feedsApi.refresh を呼び、feeds と articles を無効化する', async () => {
    vi.mocked(feedsApi.refresh).mockResolvedValue({} as never)
    const { result } = renderHook(() => useArticleMutations(1), { wrapper })

    result.current.refresh.mutate()

    await waitFor(() => expect(result.current.refresh.isSuccess).toBe(true))
    expect(feedsApi.refresh).toHaveBeenCalledWith(1)
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['feeds'] })
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['articles'] })
  })

  it('refresh は feedId が null なら feedsApi.refresh を呼ばない', async () => {
    const { result } = renderHook(() => useArticleMutations(null), { wrapper })

    result.current.refresh.mutate()

    await waitFor(() => expect(result.current.refresh.isSuccess).toBe(true))
    expect(feedsApi.refresh).not.toHaveBeenCalled()
  })

  it('markAsRead は articlesApi.markAsRead を呼び、articles のみ無効化する', async () => {
    vi.mocked(articlesApi.markAsRead).mockResolvedValue({} as never)
    const { result } = renderHook(() => useArticleMutations(1), { wrapper })

    result.current.markAsRead.mutate(5)

    await waitFor(() => expect(result.current.markAsRead.isSuccess).toBe(true))
    expect(articlesApi.markAsRead).toHaveBeenCalledWith(5)
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['articles'] })
    expect(invalidateSpy).not.toHaveBeenCalledWith({ queryKey: ['feeds'] })
  })

  it('markAsUnread は articlesApi.markAsUnread を呼び、articles のみ無効化する', async () => {
    vi.mocked(articlesApi.markAsUnread).mockResolvedValue({} as never)
    const { result } = renderHook(() => useArticleMutations(1), { wrapper })

    result.current.markAsUnread.mutate(5)

    await waitFor(() => expect(result.current.markAsUnread.isSuccess).toBe(true))
    expect(articlesApi.markAsUnread).toHaveBeenCalledWith(5)
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ['articles'] })
    expect(invalidateSpy).not.toHaveBeenCalledWith({ queryKey: ['feeds'] })
  })
})
