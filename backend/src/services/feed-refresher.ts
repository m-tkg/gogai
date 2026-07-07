import type { FeedsService } from './feeds.js'
import type { ArticlesService } from './articles.js'
import { fetchFeed } from './rss-fetcher.js'
import type { FetchedFeed } from './rss-fetcher.js'
import { toFeedFields } from './shared/feed-fields.js'

export interface RefreshResult {
  refreshed: number
  failed: number
}

async function refreshFeeds(
  feeds: { id: number; url: string }[],
  feedsService: FeedsService,
  articlesService: ArticlesService,
  fetchFeedFn: (url: string) => Promise<FetchedFeed> = fetchFeed,
): Promise<RefreshResult> {
  let refreshed = 0
  let failed = 0

  for (const feed of feeds) {
    try {
      const fetched = await fetchFeedFn(feed.url)
      articlesService.upsertMany(feed.id, fetched.items)
      feedsService.update(feed.id, toFeedFields(fetched))
      refreshed++
    } catch (e) {
      console.error(`[feed-refresher] Failed to refresh feed ${feed.url}:`, e)
      failed++
    }
  }

  return { refreshed, failed }
}

export async function refreshAllFeeds(
  feedsService: FeedsService,
  articlesService: ArticlesService,
  fetchFeedFn: (url: string) => Promise<FetchedFeed> = fetchFeed,
): Promise<RefreshResult> {
  const feeds = feedsService.findAll()
  return refreshFeeds(feeds, feedsService, articlesService, fetchFeedFn)
}

export async function refreshFeedsByGroupId(
  groupId: number,
  feedsService: FeedsService,
  articlesService: ArticlesService,
  fetchFeedFn: (url: string) => Promise<FetchedFeed> = fetchFeed,
): Promise<RefreshResult> {
  const feeds = feedsService.findByGroupId(groupId)
  return refreshFeeds(feeds, feedsService, articlesService, fetchFeedFn)
}
