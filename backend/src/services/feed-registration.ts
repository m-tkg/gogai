import { FeedsService, type Feed } from './feeds.js'
import { ArticlesService } from './articles.js'
import { discoverFeedUrl } from './feed-discovery.js'
import { fetchFeed } from './rss-fetcher.js'
import { AppError, isUniqueConstraintError } from '../errors.js'
import { toFeedFields } from './shared/feed-fields.js'

// フィード登録・URL 変更・再取得の共通フロー（discover → fetch → upsert → update）。
// エラーは AppError に正規化して投げる（ルートは onError に委譲するだけでよい）。

export async function registerFeed(
  url: string,
  groupId: number | null | undefined,
  feedsService: FeedsService,
  articlesService: ArticlesService
): Promise<Feed> {
  try {
    const feedUrl = await discoverFeedUrl(url)
    if (!feedUrl) throw new AppError('RSSフィードが見つかりませんでした', 422)

    const fetched = await fetchFeed(feedUrl)
    const { title, faviconUrl, lastFetchedAt } = toFeedFields(fetched)

    const feed = feedsService.create({
      url: feedUrl,
      title,
      faviconUrl,
      groupId: groupId ?? null,
    })

    articlesService.upsertMany(feed.id, fetched.items)
    feedsService.update(feed.id, { lastFetchedAt })

    return feed
  } catch (e: unknown) {
    throw toFeedError(e)
  }
}

export async function changeFeedUrl(
  feedId: number,
  newUrl: string,
  groupId: number | null | undefined,
  feedsService: FeedsService,
  articlesService: ArticlesService
): Promise<Feed | null> {
  try {
    const feedUrl = await discoverFeedUrl(newUrl)
    if (!feedUrl) throw new AppError('RSSフィードが見つかりませんでした', 422)

    const fetched = await fetchFeed(feedUrl)
    articlesService.upsertMany(feedId, fetched.items)
    return feedsService.update(feedId, {
      url: feedUrl,
      ...toFeedFields(fetched),
      groupId,
    })
  } catch (e: unknown) {
    throw toFeedError(e)
  }
}

export async function refetchFeed(
  feed: Feed,
  feedsService: FeedsService,
  articlesService: ArticlesService
): Promise<{ feed: Feed | null; newArticles: number }> {
  try {
    const fetched = await fetchFeed(feed.url)
    articlesService.upsertMany(feed.id, fetched.items)
    const updated = feedsService.update(feed.id, toFeedFields(fetched))
    return { feed: updated, newArticles: fetched.items.length }
  } catch (e: unknown) {
    throw toFeedError(e)
  }
}

function toFeedError(e: unknown): AppError {
  if (e instanceof AppError) return e
  if (isUniqueConstraintError(e)) return new AppError('Feed URL already exists', 409)
  const message = e instanceof Error ? e.message : 'Unknown error'
  return new AppError(`Failed to fetch feed: ${message}`, 422)
}
