import type { FetchedFeed } from '../rss-fetcher.js'

/// fetchFeed() の結果を FeedsService.create/update に渡す更新フィールドへ変換する。
export function toFeedFields(fetched: FetchedFeed): { title: string; faviconUrl: string | undefined; lastFetchedAt: string } {
  return {
    title: fetched.title,
    faviconUrl: fetched.faviconUrl !== null ? fetched.faviconUrl : undefined,
    lastFetchedAt: new Date().toISOString(),
  }
}
