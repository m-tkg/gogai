import { describe, it, expect } from 'vitest'
import { extractTextFromHtml } from '../services/article-content.js'

describe('extractTextFromHtml', () => {
  it('シンプルな HTML からテキストを抽出できる', () => {
    const html = '<p>Hello <strong>world</strong></p>'
    expect(extractTextFromHtml(html)).toBe('Hello world')
  })

  it('<article> タグ内のテキストを優先して抽出する', () => {
    const html = `
      <nav>ナビゲーション</nav>
      <article><p>本文テキスト</p></article>
      <footer>フッター</footer>
    `
    expect(extractTextFromHtml(html)).toBe('本文テキスト')
  })

  it('<main> タグ内のテキストを優先して抽出する（article がない場合）', () => {
    const html = `
      <header>ヘッダー</header>
      <main><p>メインコンテンツ</p></main>
      <footer>フッター</footer>
    `
    expect(extractTextFromHtml(html)).toBe('メインコンテンツ')
  })

  it('<script> と <style> の内容は除去する', () => {
    const html = `
      <style>body { color: red; }</style>
      <script>alert("hello")</script>
      <p>本文</p>
    `
    expect(extractTextFromHtml(html)).not.toContain('color')
    expect(extractTextFromHtml(html)).not.toContain('alert')
    expect(extractTextFromHtml(html)).toContain('本文')
  })

  it('連続する空白・改行を正規化する', () => {
    const html = '<p>テキスト1</p>   <p>テキスト2</p>'
    const result = extractTextFromHtml(html)
    expect(result).toBe('テキスト1\nテキスト2')
  })

  it('空の HTML には空文字を返す', () => {
    expect(extractTextFromHtml('')).toBe('')
    expect(extractTextFromHtml('<html><body></body></html>')).toBe('')
  })
})
