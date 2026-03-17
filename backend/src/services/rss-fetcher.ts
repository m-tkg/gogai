import Parser from 'rss-parser'

const parser = new Parser({
  customFields: {
    item: ['content:encoded', 'description']
  }
})

export interface FetchedFeed {
  title: string
  faviconUrl: string | null
  items: FetchedItem[]
}

export interface FetchedItem {
  guid: string
  title?: string
  link?: string
  summary?: string
  content?: string
  publishedAt?: string
}

export async function fetchFeed(url: string): Promise<FetchedFeed> {
  const feed = await parser.parseURL(url)

  const faviconUrl = getFaviconUrl(feed.link ?? url)

  const items: FetchedItem[] = feed.items.map(item => ({
    guid: item.guid ?? item.link ?? item.title ?? String(Date.now()),
    title: item.title,
    link: item.link,
    summary: item.contentSnippet ?? item.summary ?? stripHtml(item.description ?? ''),
    content: item['content:encoded'] ?? item.content ?? item.description,
    publishedAt: item.pubDate ? new Date(item.pubDate).toISOString() : item.isoDate,
  }))

  return {
    title: feed.title ?? url,
    faviconUrl,
    items,
  }
}

export function getFaviconUrl(siteUrl: string): string | null {
  try {
    const { origin } = new URL(siteUrl)
    return `https://www.google.com/s2/favicons?domain_url=${origin}&sz=32`
  } catch {
    return null
  }
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, '').trim().slice(0, 300)
}
