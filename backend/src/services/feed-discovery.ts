import fetch from 'node-fetch'

const CANDIDATE_PATHS = ['/feed', '/rss', '/feed.xml', '/rss.xml', '/atom.xml', '/feeds/posts/default']

const RSS_CONTENT_TYPES = ['application/rss+xml', 'application/atom+xml', 'application/xml', 'text/xml']

export async function discoverFeedUrl(url: string): Promise<string | null> {
  let response
  try {
    response = await fetch(url, { redirect: 'follow' })
  } catch {
    return null
  }

  const contentType = response.headers.get('content-type') ?? ''

  // RSS/Atom を直接指している場合はそのまま返す
  if (RSS_CONTENT_TYPES.some(t => contentType.includes(t))) {
    return url
  }

  // content-type が xml 系ならフィードとみなす
  if (contentType.includes('xml')) {
    return url
  }

  // HTML の場合は <link rel="alternate"> を探す
  if (response.ok && contentType.includes('text/html')) {
    const html = await response.text()
    const discovered = extractFeedFromHtml(html, url)
    if (discovered) return discovered
  }

  // 候補パスを順に試す
  const { origin } = new URL(url)
  for (const path of CANDIDATE_PATHS) {
    const candidateUrl = origin + path
    try {
      const res = await fetch(candidateUrl, { redirect: 'follow' })
      const ct = res.headers.get('content-type') ?? ''
      if (res.ok && (RSS_CONTENT_TYPES.some(t => ct.includes(t)) || ct.includes('xml'))) {
        return candidateUrl
      }
    } catch {
      // 次の候補へ
    }
  }

  return null
}

function extractFeedFromHtml(html: string, baseUrl: string): string | null {
  // <link rel="alternate" type="application/rss+xml" href="...">
  const pattern = /<link[^>]+rel=["']alternate["'][^>]*>/gi
  const matches = html.match(pattern) ?? []

  for (const tag of matches) {
    const typeMatch = tag.match(/type=["'](application\/(rss|atom)\+xml|text\/xml)["']/i)
    if (!typeMatch) continue

    const hrefMatch = tag.match(/href=["']([^"']+)["']/i)
    if (!hrefMatch) continue

    const href = hrefMatch[1]
    // 絶対URLか相対URLかを判定
    try {
      return new URL(href, baseUrl).toString()
    } catch {
      continue
    }
  }

  return null
}
