import { describe, it, expect } from 'vitest'
import { toFeedFields } from '../../services/shared/feed-fields.js'
import type { FetchedFeed } from '../../services/rss-fetcher.js'

describe('toFeedFields', () => {
  it('title と faviconUrl をそのまま引き継ぎ、lastFetchedAt に現在時刻の ISO 文字列を入れる', () => {
    const fetched: FetchedFeed = { title: 'Example Feed', faviconUrl: 'https://example.com/favicon.ico', items: [] }

    const fields = toFeedFields(fetched)

    expect(fields.title).toBe('Example Feed')
    expect(fields.faviconUrl).toBe('https://example.com/favicon.ico')
    expect(new Date(fields.lastFetchedAt).toISOString()).toBe(fields.lastFetchedAt)
  })

  it('faviconUrl が null なら undefined に変換する', () => {
    const fetched: FetchedFeed = { title: 'Example Feed', faviconUrl: null, items: [] }

    const fields = toFeedFields(fetched)

    expect(fields.faviconUrl).toBeUndefined()
  })
})
