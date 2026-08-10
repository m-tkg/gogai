import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type Database from 'better-sqlite3'
import { ArticlesService } from '../services/articles.js'
import { FeedsService } from '../services/feeds.js'
import { GroupsService } from '../services/groups.js'
import { createTestDb } from './helpers/db.js'

let db: Database.Database
let articlesService: ArticlesService
let feedsService: FeedsService
let feedId: number

beforeEach(() => {
  db = createTestDb()
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

  it('フィードリフレッシュ後も既読状態は保持される', () => {
    const item = { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: 'Summary', publishedAt: new Date().toISOString() }
    articlesService.upsertMany(feedId, [item])
    const article = articlesService.findByFeed(feedId)[0]
    articlesService.markAsRead(article.id)

    // フィードリフレッシュ時と同じ操作（内容が更新された同一記事を再 upsert）
    articlesService.upsertMany(feedId, [{ ...item, title: '更新されたタイトル' }])

    const [updated] = articlesService.findByFeed(feedId)
    expect(updated.is_read).toBe(1)
    expect(updated.title).toBe('更新されたタイトル')
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

  describe('like（キュレーター向けの好みフラグ）', () => {
    let articleId: number

    beforeEach(() => {
      articlesService.upsertMany(feedId, [
        { guid: 'g1', title: 'A1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() },
      ])
      articleId = articlesService.findByFeed(feedId)[0].id
    })

    it('like すると liked_at が入る', () => {
      articlesService.like(articleId)
      expect(articlesService.findById(articleId)?.liked_at).toBeTypeOf('string')
    })

    it('unlike すると liked_at が null に戻る', () => {
      articlesService.like(articleId)
      articlesService.unlike(articleId)
      expect(articlesService.findById(articleId)?.liked_at).toBeNull()
    })

    it('存在しない id を like してもエラーにならない（既読と同じ作法）', () => {
      expect(() => articlesService.like(9999)).not.toThrow()
      expect(() => articlesService.unlike(9999)).not.toThrow()
    })

    it('likedOnly=true で like 済みの記事のみ返す', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
      ])
      articlesService.like(articleId)

      const result = articlesService.findAll({ limit: 10, offset: 0, likedOnly: true })
      expect(result).toHaveLength(1)
      expect(result[0].guid).toBe('g1')
    })

    it('likedOnly=true は sortBy を無視して liked_at 降順で返す', () => {
      // g2 の方が配信日は古いが、like したのは後 → liked_at 降順では g2 が先に来る
      articlesService.upsertMany(feedId, [
        { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: '2020-01-01T00:00:00.000Z' },
      ])
      const g2 = articlesService.findByFeed(feedId).find((a) => a.guid === 'g2')!
      articlesService.like(articleId, '2026-01-01T00:00:00.000Z')
      articlesService.like(g2.id, '2026-02-01T00:00:00.000Z')

      const result = articlesService.findAll({ limit: 10, offset: 0, likedOnly: true, sortBy: 'published_at' })
      expect(result.map((a) => a.guid)).toEqual(['g2', 'g1'])
    })

    it('like された記事は retention の削除対象から除外される', () => {
      const now = new Date()
      const old = new Date(now.getTime() - 200 * 24 * 60 * 60 * 1000) // 200日前

      articlesService.upsertMany(feedId, [
        { guid: 'old-liked', title: 'Old Liked', link: 'https://example.com/old-liked', summary: '', publishedAt: old.toISOString() },
        { guid: 'old-plain', title: 'Old Plain', link: 'https://example.com/old-plain', summary: '', publishedAt: old.toISOString() },
      ])
      const oldLiked = articlesService.findByFeed(feedId).find((a) => a.guid === 'old-liked')!
      articlesService.like(oldLiked.id)

      const threshold = new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000)
      const deleted = articlesService.deleteOlderThan(threshold)

      expect(deleted).toBe(1)
      const remaining = articlesService.findByFeed(feedId).map((a) => a.guid)
      expect(remaining).toContain('old-liked')
      expect(remaining).not.toContain('old-plain')
    })

    it('unlike した記事は再び retention の削除対象になる', () => {
      const now = new Date()
      const old = new Date(now.getTime() - 200 * 24 * 60 * 60 * 1000)

      articlesService.upsertMany(feedId, [
        { guid: 'old-1', title: 'Old', link: 'https://example.com/old', summary: '', publishedAt: old.toISOString() },
      ])
      const oldArticle = articlesService.findByFeed(feedId).find((a) => a.guid === 'old-1')!
      articlesService.like(oldArticle.id)
      articlesService.unlike(oldArticle.id)

      const threshold = new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000)
      expect(articlesService.deleteOlderThan(threshold)).toBe(1)
    })

    it('countsByFeed が liked 件数を返す', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
      ])
      articlesService.like(articleId)

      const counts = articlesService.countsByFeed()
      expect(counts).toHaveLength(1)
      expect(counts[0]).toEqual({ feed_id: feedId, total: 2, unread: 2, liked: 1, disliked: 0 })
    })
  })

  describe('dislike（好みでないことを示す負のシグナル）', () => {
    let articleId: number

    beforeEach(() => {
      articlesService.upsertMany(feedId, [
        { guid: 'g1', title: 'A1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() },
      ])
      articleId = articlesService.findByFeed(feedId)[0].id
    })

    it('dislike すると disliked_at が入る', () => {
      articlesService.dislike(articleId)
      expect(articlesService.findById(articleId)?.disliked_at).toBeTypeOf('string')
    })

    it('undislike すると disliked_at が null に戻る', () => {
      articlesService.dislike(articleId)
      articlesService.undislike(articleId)
      expect(articlesService.findById(articleId)?.disliked_at).toBeNull()
    })

    it('存在しない id を dislike してもエラーにならない', () => {
      expect(() => articlesService.dislike(9999)).not.toThrow()
      expect(() => articlesService.undislike(9999)).not.toThrow()
    })

    // like と dislike は排他。同じ記事が両方の評価を持つ状態を作らせない
    it('like 済みの記事を dislike すると like が外れる', () => {
      articlesService.like(articleId)
      articlesService.dislike(articleId)

      const article = articlesService.findById(articleId)
      expect(article?.disliked_at).toBeTypeOf('string')
      expect(article?.liked_at).toBeNull()
    })

    it('dislike 済みの記事を like すると dislike が外れる', () => {
      articlesService.dislike(articleId)
      articlesService.like(articleId)

      const article = articlesService.findById(articleId)
      expect(article?.liked_at).toBeTypeOf('string')
      expect(article?.disliked_at).toBeNull()
    })

    it('unlike は dislike の状態を変えない', () => {
      articlesService.dislike(articleId)
      articlesService.unlike(articleId)
      expect(articlesService.findById(articleId)?.disliked_at).toBeTypeOf('string')
    })

    it('dislikedOnly=true で dislike 済みの記事のみ返す', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
      ])
      articlesService.dislike(articleId)

      const result = articlesService.findAll({ limit: 10, offset: 0, dislikedOnly: true })
      expect(result).toHaveLength(1)
      expect(result[0].guid).toBe('g1')
    })

    it('dislikedOnly=true は sortBy を無視して disliked_at 降順で返す', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: '2020-01-01T00:00:00.000Z' },
      ])
      const g2 = articlesService.findByFeed(feedId).find((a) => a.guid === 'g2')!
      articlesService.dislike(articleId, '2026-01-01T00:00:00.000Z')
      articlesService.dislike(g2.id, '2026-02-01T00:00:00.000Z')

      const result = articlesService.findAll({ limit: 10, offset: 0, dislikedOnly: true, sortBy: 'published_at' })
      expect(result.map((a) => a.guid)).toEqual(['g2', 'g1'])
    })

    it('dislike された記事も retention の削除対象から除外される', () => {
      const now = new Date()
      const old = new Date(now.getTime() - 200 * 24 * 60 * 60 * 1000)

      articlesService.upsertMany(feedId, [
        { guid: 'old-disliked', title: 'Old Disliked', link: 'https://example.com/old-d', summary: '', publishedAt: old.toISOString() },
        { guid: 'old-plain', title: 'Old Plain', link: 'https://example.com/old-p', summary: '', publishedAt: old.toISOString() },
      ])
      const oldDisliked = articlesService.findByFeed(feedId).find((a) => a.guid === 'old-disliked')!
      articlesService.dislike(oldDisliked.id)

      const threshold = new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000)
      expect(articlesService.deleteOlderThan(threshold)).toBe(1)

      const remaining = articlesService.findByFeed(feedId).map((a) => a.guid)
      expect(remaining).toContain('old-disliked')
      expect(remaining).not.toContain('old-plain')
    })

    it('countsByFeed が disliked 件数を返す', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g2', title: 'A2', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
      ])
      articlesService.dislike(articleId)

      const counts = articlesService.countsByFeed()
      expect(counts[0]).toEqual({ feed_id: feedId, total: 2, unread: 2, liked: 0, disliked: 1 })
    })
  })

  describe('ソート機能', () => {
    it('配信日順（デフォルト）でソートできる', () => {
      const now = new Date()
      const older = new Date(now.getTime() - 2 * 24 * 60 * 60 * 1000) // 2日前
      const newer = new Date(now.getTime() - 1 * 24 * 60 * 60 * 1000) // 1日前

      articlesService.upsertMany(feedId, [
        { guid: 'g-old', title: 'Old Article', link: 'https://example.com/old', summary: '', publishedAt: older.toISOString() },
        { guid: 'g-new', title: 'New Article', link: 'https://example.com/new', summary: '', publishedAt: newer.toISOString() },
      ])

      const articles = articlesService.findAll({ limit: 10, offset: 0, sortBy: 'published_at' })
      expect(articles[0].title).toBe('New Article')
      expect(articles[1].title).toBe('Old Article')
    })

    it('既読日時順でソートできる', () => {
      const now = new Date()
      const older = new Date(now.getTime() - 2 * 24 * 60 * 60 * 1000) // 2日前
      const newer = new Date(now.getTime() - 1 * 24 * 60 * 60 * 1000) // 1日前

      articlesService.upsertMany(feedId, [
        { guid: 'g-old', title: 'Old Article', link: 'https://example.com/old', summary: '', publishedAt: older.toISOString() },
        { guid: 'g-new', title: 'New Article', link: 'https://example.com/new', summary: '', publishedAt: newer.toISOString() },
      ])

      const allArticles = articlesService.findByFeed(feedId)
      const oldArticle = allArticles.find(a => a.title === 'Old Article')!
      const newArticle = allArticles.find(a => a.title === 'New Article')!

      // 古い記事を先に既読にする（read_at が早い）
      const readAtOld = new Date(now.getTime() - 60 * 60 * 1000).toISOString() // 1時間前
      const readAtNew = new Date(now.getTime() - 30 * 60 * 1000).toISOString() // 30分前
      articlesService.markAsRead(oldArticle.id, readAtOld)
      articlesService.markAsRead(newArticle.id, readAtNew)

      const articles = articlesService.findAll({ limit: 10, offset: 0, sortBy: 'read_at' })
      // read_at が新しい順なので、後で既読にした New Article が先
      expect(articles[0].title).toBe('New Article')
      expect(articles[1].title).toBe('Old Article')
    })

    it('既読日時順で未読記事は published_at で扱う', () => {
      const now = new Date()
      const recentPublishedAt = new Date(now.getTime() - 30 * 60 * 1000) // 30分前

      articlesService.upsertMany(feedId, [
        { guid: 'g-read', title: 'Read Article', link: 'https://example.com/read', summary: '', publishedAt: new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000).toISOString() },
        { guid: 'g-unread', title: 'Unread Article', link: 'https://example.com/unread', summary: '', publishedAt: recentPublishedAt.toISOString() },
      ])

      const allArticles = articlesService.findByFeed(feedId)
      const readArticle = allArticles.find(a => a.title === 'Read Article')!
      articlesService.markAsRead(readArticle.id)

      // readArticle の read_at は現在時刻近くなるが、unread の published_at (30分前) より古い
      // ただし read_at が最新なので Read Article が先のはず
      const articles = articlesService.findAll({ limit: 10, offset: 0, sortBy: 'read_at' })
      // read_at が最新（今）の Read Article が先
      expect(articles[0].title).toBe('Read Article')
      // 未読の Unread Article は published_at = 30分前 なので後
      expect(articles[1].title).toBe('Unread Article')
    })

    it('markAsRead で read_at が記録される', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() }
      ])
      const article = articlesService.findByFeed(feedId)[0]
      expect(article.read_at).toBeNull()

      articlesService.markAsRead(article.id)
      const updated = articlesService.findById(article.id)
      expect(updated?.read_at).not.toBeNull()
    })

    it('markAsUnread で read_at がクリアされる', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'guid-1', title: 'Article 1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() }
      ])
      const article = articlesService.findByFeed(feedId)[0]
      articlesService.markAsRead(article.id)
      articlesService.markAsUnread(article.id)
      const updated = articlesService.findById(article.id)
      expect(updated?.read_at).toBeNull()
    })
  })

  describe('シークレットグループのフィルタリング', () => {
    let secretFeedId: number

    beforeEach(() => {
      const groupsService = new GroupsService(db)
      const secretGroup = groupsService.create('SecretGroup', 1)
      const secretFeed = feedsService.create({ url: 'https://secret.com/feed.xml', title: 'Secret Feed', groupId: secretGroup.id })
      secretFeedId = secretFeed.id

      articlesService.upsertMany(feedId, [
        { guid: 'public-1', title: 'Public Article', link: 'https://example.com/1', summary: '' },
      ])
      articlesService.upsertMany(secretFeedId, [
        { guid: 'secret-1', title: 'Secret Article', link: 'https://secret.com/1', summary: '' },
      ])
    })

    it('デフォルトではシークレットグループの記事を除外する', () => {
      const articles = articlesService.findAll({ limit: 10, offset: 0 })
      expect(articles.map(a => a.title)).not.toContain('Secret Article')
      expect(articles.map(a => a.title)).toContain('Public Article')
    })

    it('includeSecret=true のときシークレットグループの記事を含む', () => {
      const articles = articlesService.findAll({ limit: 10, offset: 0, includeSecret: true })
      expect(articles.map(a => a.title)).toContain('Secret Article')
      expect(articles.map(a => a.title)).toContain('Public Article')
    })

    it('groupId を指定した場合はシークレットグループでも記事を取得できる', () => {
      const secretGroup = new GroupsService(db).findAll().find(g => g.name === 'SecretGroup')!
      const articles = articlesService.findAll({ limit: 10, offset: 0, groupId: secretGroup.id })
      expect(articles.map(a => a.title)).toContain('Secret Article')
    })
  })

  describe('countsByFeed', () => {
    it('フィードごとの total / unread を集計する', () => {
      const feed2 = feedsService.create({ url: 'https://example2.com/feed.xml', title: 'Example2' })
      articlesService.upsertMany(feedId, [
        { guid: 'c1', title: 'A1', link: 'https://example.com/c1', summary: '' },
        { guid: 'c2', title: 'A2', link: 'https://example.com/c2', summary: '' },
        { guid: 'c3', title: 'A3', link: 'https://example.com/c3', summary: '' },
      ])
      articlesService.upsertMany(feed2.id, [
        { guid: 'c4', title: 'B1', link: 'https://example2.com/c4', summary: '' },
      ])
      const feed1Articles = articlesService.findByFeed(feedId)
      articlesService.markAsRead(feed1Articles[0].id)

      const counts = articlesService.countsByFeed()
      const feed1Count = counts.find(c => c.feed_id === feedId)
      const feed2Count = counts.find(c => c.feed_id === feed2.id)
      expect(feed1Count).toEqual({ feed_id: feedId, total: 3, unread: 2, liked: 0, disliked: 0 })
      expect(feed2Count).toEqual({ feed_id: feed2.id, total: 1, unread: 1, liked: 0, disliked: 0 })
    })

    it('シークレットグループのフィードも集計に含む', () => {
      const groupsService = new GroupsService(db)
      const secretGroup = groupsService.create('SecretGroup', 1)
      const secretFeed = feedsService.create({ url: 'https://secret.com/feed.xml', title: 'Secret Feed', groupId: secretGroup.id })
      articlesService.upsertMany(secretFeed.id, [
        { guid: 's1', title: 'Secret Article', link: 'https://secret.com/1', summary: '' },
      ])

      const counts = articlesService.countsByFeed()
      const secretCount = counts.find(c => c.feed_id === secretFeed.id)
      expect(secretCount).toEqual({ feed_id: secretFeed.id, total: 1, unread: 1, liked: 0, disliked: 0 })
    })

    it('記事が 0 件のフィードは結果に含まれない', () => {
      const emptyFeed = feedsService.create({ url: 'https://empty.com/feed.xml', title: 'Empty' })
      const counts = articlesService.countsByFeed()
      expect(counts.find(c => c.feed_id === emptyFeed.id)).toBeUndefined()
    })
  })

  describe('重複URLの自動既読', () => {
    let feed2Id: number

    beforeEach(() => {
      const feed2 = feedsService.create({ url: 'https://example2.com/feed.xml', title: 'Example2' })
      feed2Id = feed2.id
    })

    it('同一URLが別フィードに先に存在する場合、後から登録した記事を自動既読にする', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g1', title: 'Article from Feed1', link: 'https://shared.example.com/article', summary: '' }
      ])
      articlesService.upsertMany(feed2Id, [
        { guid: 'g2', title: 'Article from Feed2', link: 'https://shared.example.com/article', summary: '' }
      ])

      expect(articlesService.findByFeed(feedId)[0].is_read).toBe(0)  // 先に登録した方は未読のまま
      expect(articlesService.findByFeed(feed2Id)[0].is_read).toBe(1) // 後から登録した方が自動既読
    })

    it('同一URLが別フィードに存在しない場合は自動既読にしない', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g1', title: 'Unique Article', link: 'https://example.com/unique', summary: '' }
      ])
      expect(articlesService.findByFeed(feedId)[0].is_read).toBe(0)
    })

    it('link が null の記事は重複チェックをしない', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g1', title: 'No Link Article 1', summary: '' }
      ])
      articlesService.upsertMany(feed2Id, [
        { guid: 'g2', title: 'No Link Article 2', summary: '' }
      ])

      expect(articlesService.findByFeed(feed2Id)[0].is_read).toBe(0)
    })

    it('フィードリフレッシュ時に新たに重複するURLの記事を自動既読にする', () => {
      articlesService.upsertMany(feedId, [
        { guid: 'g1', title: 'Original Article', link: 'https://shared.example.com/article', summary: '' }
      ])
      articlesService.upsertMany(feed2Id, [
        { guid: 'g3', title: 'Different Article', link: 'https://different.example.com/article', summary: '' }
      ])
      // リフレッシュで feed2 に重複URLの記事が追加される
      articlesService.upsertMany(feed2Id, [
        { guid: 'g3', title: 'Different Article', link: 'https://different.example.com/article', summary: '' },
        { guid: 'g4', title: 'Now Shared Article', link: 'https://shared.example.com/article', summary: '' },
      ])

      const feed2Articles = articlesService.findByFeed(feed2Id)
      const sharedArticle = feed2Articles.find(a => a.link === 'https://shared.example.com/article')
      expect(sharedArticle?.is_read).toBe(1)
    })
  })
})
