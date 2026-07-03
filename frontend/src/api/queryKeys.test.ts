import { describe, it, expect, vi } from 'vitest'
import { QueryClient } from '@tanstack/react-query'
import { queryKeys, invalidateArticles, invalidateFeedsAndArticles } from './queryKeys'

describe('queryKeys', () => {
  it('一覧キーは固定の配列を返す', () => {
    expect(queryKeys.groups).toEqual(['groups'])
    expect(queryKeys.feeds).toEqual(['feeds'])
    expect(queryKeys.articles).toEqual(['articles'])
    expect(queryKeys.settings).toEqual(['settings'])
    expect(queryKeys.updateCheck).toEqual(['update-check'])
  })

  it('articleList はフィルター付きのキーを返し、articles を接頭辞に持つ', () => {
    const filter = { feedId: 1, groupId: null, unreadOnly: true, sortBy: 'published_at' as const, showSecretGroups: false }
    const key = queryKeys.articleList(filter)
    expect(key[0]).toBe(queryKeys.articles[0])
    expect(key[1]).toEqual(filter)
  })

  it('invalidateArticles は articles 配下のクエリを無効化する', () => {
    const qc = new QueryClient()
    const spy = vi.spyOn(qc, 'invalidateQueries')
    invalidateArticles(qc)
    expect(spy).toHaveBeenCalledWith({ queryKey: ['articles'] })
  })

  it('invalidateFeedsAndArticles は feeds と articles を無効化する', () => {
    const qc = new QueryClient()
    const spy = vi.spyOn(qc, 'invalidateQueries')
    invalidateFeedsAndArticles(qc)
    expect(spy).toHaveBeenCalledWith({ queryKey: ['feeds'] })
    expect(spy).toHaveBeenCalledWith({ queryKey: ['articles'] })
  })
})
