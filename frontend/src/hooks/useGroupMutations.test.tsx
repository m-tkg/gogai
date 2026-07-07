import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useGroupMutations } from './useGroupMutations'

vi.mock('../api/client', () => ({
  groupsApi: {
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    refresh: vi.fn(),
    reorder: vi.fn(),
  },
}))

import { groupsApi } from '../api/client'

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
