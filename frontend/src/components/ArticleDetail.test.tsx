import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { ArticleDetail } from './ArticleDetail'
import type { Article } from '../api/client'

function makeArticle(over: Partial<Article> = {}): Article {
  return {
    id: 1,
    feed_id: 1,
    guid: 'g1',
    title: 'Title',
    link: null,
    summary: null,
    content: null,
    published_at: null,
    is_read: 0,
    created_at: '2024-01-01T00:00:00Z',
    read_at: null,
    ...over,
  }
}

describe('ArticleDetail の本文サニタイズ（XSS 対策）', () => {
  it('<script> タグは除去される', () => {
    const { container } = render(
      <ArticleDetail article={makeArticle({ content: '<p>本文</p><script>alert(1)</script>' })} />
    )
    expect(container.innerHTML).not.toContain('<script')
    expect(container.querySelector('p')?.textContent).toBe('本文')
  })

  it('onerror などのイベントハンドラ属性は除去される（属性ベース XSS 対策）', () => {
    const { container } = render(
      <ArticleDetail article={makeArticle({ content: '<img src="x.png" onerror="alert(1)">' })} />
    )
    const img = container.querySelector('img')
    expect(img).not.toBeNull()
    expect(img?.getAttribute('onerror')).toBeNull()
  })

  it('<a> タグには target=_blank と rel=noopener noreferrer が強制される', () => {
    const { container } = render(
      <ArticleDetail article={makeArticle({ content: '<a href="https://example.com">link</a>' })} />
    )
    const a = container.querySelector('a')
    expect(a?.getAttribute('target')).toBe('_blank')
    expect(a?.getAttribute('rel')).toBe('noopener noreferrer')
  })

  it('javascript: スキームの href は無効化される', () => {
    const { container } = render(
      <ArticleDetail article={makeArticle({ content: '<a href="javascript:alert(1)">click</a>' })} />
    )
    const a = container.querySelector('a')
    expect(a?.getAttribute('href')).not.toBe('javascript:alert(1)')
  })

  it('通常のタグ・テキストはそのまま表示される', () => {
    const { container } = render(
      <ArticleDetail article={makeArticle({ content: '<p>Hello <b>World</b></p>' })} />
    )
    expect(container.querySelector('b')?.textContent).toBe('World')
  })
})
