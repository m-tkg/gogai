import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { ArticlesService } from '../services/articles.js'
import { FeedsService } from '../services/feeds.js'

let db: Database.Database
let articlesService: ArticlesService
let feedsService: FeedsService
let feedId: number

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  articlesService = new ArticlesService(db)
  feedsService = new FeedsService(db)
  const feed = feedsService.create({ url: 'https://example.com/feed.xml', title: 'Example' })
  feedId = feed.id
})

afterEach(() => {
  db.close()
})

describe('ArticlesService', () => {
  it('記事を保存できる', () => {
    articlesService.upsertMany(feedId, [
      { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: 'Summary 1', publishedAt: new Date().toISOString() }
    ])
    const articles = articlesService.findByFeed(feedId)
    expect(articles).toHaveLength(1)
    expect(articles[0].title).toBe('Article 1')
  })

  it('同じguidの記事は重複保存しない', () => {
    const item = { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: 'Summary', publishedAt: new Date().toISOString() }
    articlesService.upsertMany(feedId, [item])
    articlesService.upsertMany(feedId, [item])
    expect(articlesService.findByFeed(feedId)).toHaveLength(1)
  })

  it('全フィードの記事を取得できる', () => {
    articlesService.upsertMany(feedId, [
      { guid: 'g1', title: 'A1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() },
      { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
    ])
    expect(articlesService.findAll({ limit: 10, offset: 0 })).toHaveLength(2)
  })

  it('記事を既読にできる', () => {
    articlesService.upsertMany(feedId, [
      { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() }
    ])
    const article = articlesService.findByFeed(feedId)[0]
    articlesService.markAsRead(article.id)
    const updated = articlesService.findById(article.id)
    expect(updated?.is_read).toBe(1)
  })

  it('フィード削除時に記事も削除される', () => {
    articlesService.upsertMany(feedId, [
      { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() }
    ])
    feedsService.remove(feedId)
    expect(articlesService.findByFeed(feedId)).toHaveLength(0)
  })

  it('指定日より古い記事を削除できる', () => {
    const now = new Date()
    const old = new Date(now.getTime() - 200 * 24 * 60 * 60 * 1000) // 200日前
    const recent = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000) // 30日前

    articlesService.upsertMany(feedId, [
      { guid: 'old-1', title: 'Old Article', link: 'https://example.com/old', summary: '', publishedAt: old.toISOString() },
      { guid: 'new-1', title: 'Recent Article', link: 'https://example.com/new', summary: '', publishedAt: recent.toISOString() },
    ])

    const threshold = new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000) // 半年前(180日)
    const deleted = articlesService.deleteOlderThan(threshold)

    expect(deleted).toBe(1)
    expect(articlesService.findByFeed(feedId)).toHaveLength(1)
    expect(articlesService.findByFeed(feedId)[0].title).toBe('Recent Article')
  })

  it('published_at が null の記事は created_at で削除判定する', () => {
    articlesService.upsertMany(feedId, [
      { guid: 'no-date', title: 'No Date Article', link: 'https://example.com/no-date', summary: '' },
    ])

    // created_at は INSERT 直後なので未来の threshold では削除されない
    const futureThreshold = new Date(Date.now() + 1000)
    const deleted = articlesService.deleteOlderThan(futureThreshold)

    expect(deleted).toBe(1)
    expect(articlesService.findByFeed(feedId)).toHaveLength(0)
  })

  it('published_at が null かつ created_at が新しい記事は削除しない', () => {
    articlesService.upsertMany(feedId, [
      { guid: 'no-date-new', title: 'New No Date Article', link: 'https://example.com/no-date', summary: '' },
    ])

    // created_at より前の threshold なので削除されない
    const pastThreshold = new Date(Date.now() - 1000)
    const deleted = articlesService.deleteOlderThan(pastThreshold)

    expect(deleted).toBe(0)
    expect(articlesService.findByFeed(feedId)).toHaveLength(1)
  })
})
