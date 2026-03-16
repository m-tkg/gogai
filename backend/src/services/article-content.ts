import fetch from 'node-fetch'

// スクリプト・スタイル等ノイズタグを内容ごと除去
const NOISE_TAGS = ['script', 'style', 'nav', 'header', 'footer', 'aside', 'head']

export function extractTextFromHtml(html: string): string {
  let text = html

  // ノイズタグを内容ごと除去
  for (const tag of NOISE_TAGS) {
    text = text.replace(new RegExp(`<${tag}[^>]*>[\\s\\S]*?<\\/${tag}>`, 'gi'), ' ')
  }

  // <article> か <main> の内容を優先抽出
  const articleMatch = text.match(/<article[^>]*>([\s\S]*?)<\/article>/i)
  const mainMatch = text.match(/<main[^>]*>([\s\S]*?)<\/main>/i)
  if (articleMatch) text = articleMatch[1]
  else if (mainMatch) text = mainMatch[1]

  // ブロック要素の境界を改行に変換
  text = text.replace(/<\/?(p|div|h[1-6]|li|br|section)[^>]*>/gi, '\n')

  // 残りの HTML タグを除去
  text = text.replace(/<[^>]*>/g, '')

  // HTML エンティティをデコード
  text = text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')

  // 空白・改行を正規化
  text = text
    .split('\n')
    .map(line => line.replace(/\s+/g, ' ').trim())
    .filter(line => line.length > 0)
    .join('\n')

  return text
}

export async function fetchArticleContent(url: string): Promise<string> {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'Mozilla/5.0 (compatible; RSSReader/1.0)' },
    redirect: 'follow',
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const html = await res.text()
  return extractTextFromHtml(html)
}
