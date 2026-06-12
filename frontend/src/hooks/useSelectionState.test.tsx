import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useSelectionState } from './useSelectionState'
import { useDarkMode } from './useDarkMode'
import { useLocalStorageBool } from './useLocalStorageBool'
import type { Article } from '../api/client'

const article: Article = {
  id: 1, feed_id: 1, guid: 'g', title: 'T', link: null, summary: null,
  content: null, published_at: null, is_read: 0, is_favorite: 0,
  created_at: '', read_at: null,
}

describe('useSelectionState', () => {
  it('初期状態は何も選択されていない', () => {
    const { result } = renderHook(() => useSelectionState())
    expect(result.current.feedId).toBeNull()
    expect(result.current.groupId).toBeNull()
    expect(result.current.article).toBeNull()
    expect(result.current.showSettings).toBe(false)
    expect(result.current.mobileView).toBe('list')
  })

  it('selectFeed は記事選択・設定表示をリセットし list 表示へ戻す', () => {
    const { result } = renderHook(() => useSelectionState())
    act(() => result.current.selectArticle(article))
    act(() => result.current.openSettings())
    act(() => result.current.selectFeed(5))

    expect(result.current.feedId).toBe(5)
    expect(result.current.article).toBeNull()
    expect(result.current.showSettings).toBe(false)
    expect(result.current.mobileView).toBe('list')
  })

  it('selectGroup も同様にリセットする', () => {
    const { result } = renderHook(() => useSelectionState())
    act(() => result.current.selectArticle(article))
    act(() => result.current.selectGroup(3))

    expect(result.current.groupId).toBe(3)
    expect(result.current.article).toBeNull()
    expect(result.current.mobileView).toBe('list')
  })

  it('selectArticle は記事を保持して detail 表示に切り替える', () => {
    const { result } = renderHook(() => useSelectionState())
    act(() => result.current.selectArticle(article))
    expect(result.current.article).toEqual(article)
    expect(result.current.mobileView).toBe('detail')
  })

  it('backToList は mobileView のみ list に戻す', () => {
    const { result } = renderHook(() => useSelectionState())
    act(() => result.current.selectArticle(article))
    act(() => result.current.backToList())
    expect(result.current.mobileView).toBe('list')
    expect(result.current.article).toEqual(article)
  })
})

describe('useDarkMode', () => {
  beforeEach(() => {
    localStorage.clear()
    document.documentElement.classList.remove('dark')
  })

  it('localStorage の保存値を初期値に使う', () => {
    localStorage.setItem('darkMode', 'true')
    const { result } = renderHook(() => useDarkMode())
    expect(result.current.darkMode).toBe(true)
    expect(document.documentElement.classList.contains('dark')).toBe(true)
  })

  it('toggle で document クラスと localStorage が更新される', () => {
    localStorage.setItem('darkMode', 'false')
    const { result } = renderHook(() => useDarkMode())

    act(() => result.current.toggleDarkMode())
    expect(result.current.darkMode).toBe(true)
    expect(document.documentElement.classList.contains('dark')).toBe(true)
    expect(localStorage.getItem('darkMode')).toBe('true')
  })
})

describe('useLocalStorageBool', () => {
  beforeEach(() => localStorage.clear())

  it('保存値がなければデフォルト値を使う', () => {
    const { result } = renderHook(() => useLocalStorageBool('sidebarOpen', true))
    expect(result.current[0]).toBe(true)
  })

  it('toggle すると localStorage に保存される', () => {
    localStorage.setItem('sidebarOpen', 'true')
    const { result } = renderHook(() => useLocalStorageBool('sidebarOpen', true))

    act(() => result.current[1]())
    expect(result.current[0]).toBe(false)
    expect(localStorage.getItem('sidebarOpen')).toBe('false')
  })
})
