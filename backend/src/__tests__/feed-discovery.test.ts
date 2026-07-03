import { describe, it, expect, vi, beforeEach } from 'vitest'
import { discoverFeedUrl } from '../services/feed-discovery.js'

// node-fetch をモック
vi.mock('node-fetch', () => ({
  default: vi.fn(),
}))

import fetch from 'node-fetch'
const mockFetch = vi.mocked(fetch)

function makeResponse(body: string, contentType: string, status = 200) {
  return {
    ok: status < 400,
    status,
    headers: { get: (key: string) => key === 'content-type' ? contentType : null },
    text: async () => body,
  } as unknown as Awaited<ReturnType<typeof fetch>>
}

beforeEach(() => {
  mockFetch.mockReset()
})

describe('discoverFeedUrl', () => {
  it('RSS URLを直接渡したらそのまま返す', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse('<rss version="2.0"></rss>', 'application/rss+xml'))
    const result = await discoverFeedUrl('https://example.com/feed.xml')
    expect(result).toBe('https://example.com/feed.xml')
  })

  it('Atom URLを直接渡したらそのまま返す', async () => {
    mockFetch.mockResolvedValueOnce(makeResponse('<feed xmlns="http://www.w3.org/2005/Atom"></feed>', 'application/atom+xml'))
    const result = await discoverFeedUrl('https://example.com/atom.xml')
    expect(result).toBe('https://example.com/atom.xml')
  })

  it('HTMLの<link>タグからRSSフィードを検出する', async () => {
    const html = `<html><head>
      <link rel="alternate" type="application/rss+xml" href="/feed" title="RSS">
    </head></html>`
    mockFetch.mockResolvedValueOnce(makeResponse(html, 'text/html'))
    const result = await discoverFeedUrl('https://example.com/')
    expect(result).toBe('https://example.com/feed')
  })

  it('HTMLの<link>タグから絶対URLのフィードを検出する', async () => {
    const html = `<html><head>
      <link rel="alternate" type="application/atom+xml" href="https://example.com/atom.xml">
    </head></html>`
    mockFetch.mockResolvedValueOnce(makeResponse(html, 'text/html'))
    const result = await discoverFeedUrl('https://example.com/')
    expect(result).toBe('https://example.com/atom.xml')
  })

  it('linkタグがなければ候補パスを順に試す', async () => {
    const html = `<html><head><title>No feed link</title></head></html>`
    mockFetch
      .mockResolvedValueOnce(makeResponse(html, 'text/html'))            // トップページ (HTML)
      .mockResolvedValueOnce(makeResponse('Not Found', 'text/html', 404)) // /feed
      .mockResolvedValueOnce(makeResponse('<rss></rss>', 'application/rss+xml')) // /rss
    const result = await discoverFeedUrl('https://example.com/')
    expect(result).toBe('https://example.com/rss')
  })

  it('フィードが見つからない場合はnullを返す', async () => {
    const html = `<html><head><title>No feed</title></head></html>`
    mockFetch.mockResolvedValue(makeResponse('Not Found', 'text/html', 404))
    mockFetch.mockResolvedValueOnce(makeResponse(html, 'text/html'))
    const result = await discoverFeedUrl('https://example.com/')
    expect(result).toBeNull()
  })
})
