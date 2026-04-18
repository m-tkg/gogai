import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { ArticlesService } from '../services/articles.js'
import { FeedsService } from '../services/feeds.js'
import { GroupsService } from '../services/groups.js'

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

  describe('AI キャッシュ', () => {
    let articleId: number

    beforeEach(() => {
      articlesService.upsertMany(feedId, [
        { guid: 'ai-test', title: 'AI Test Article', link: 'https://example.com/ai', summary: 'summary' },
      ])
      articleId = articlesService.findByFeed(feedId)[0].id
    })

    it('要約結果を保存して取得できる', () => {
      articlesService.saveAiResult(articleId, 'summarize', 'これは要約です')
      const article = articlesService.findById(articleId)
      expect(article?.ai_summary).toBe('これは要約です')
      expect(article?.ai_translation).toBeNull()
    })

    it('翻訳結果を保存して取得できる', () => {
      articlesService.saveAiResult(articleId, 'translate', 'これは翻訳です')
      const article = articlesService.findById(articleId)
      expect(article?.ai_translation).toBe('これは翻訳です')
      expect(article?.ai_summary).toBeNull()
    })

    it('上書き保存できる', () => {
      articlesService.saveAiResult(articleId, 'summarize', '最初の要約')
      articlesService.saveAiResult(articleId, 'summarize', '更新した要約')
      expect(articlesService.findById(articleId)?.ai_summary).toBe('更新した要約')
    })

    it('空文字列は保存しない（既存値も保持）', () => {
      articlesService.saveAiResult(articleId, 'summarize', '本物の要約')
      articlesService.saveAiResult(articleId, 'summarize', '')
      expect(articlesService.findById(articleId)?.ai_summary).toBe('本物の要約')
    })

    it('AI 結果が空文字列のとき DB には NULL のまま', () => {
      articlesService.saveAiResult(articleId, 'translate', '')
      expect(articlesService.findById(articleId)?.ai_translation).toBeNull()
    })
  })

  describe('summaryOnly フィルタリング', () => {
    let articleWithSummaryId: number
    let articleWithoutSummaryId: number

    beforeEach(() => {
      articlesService.upsertMany(feedId, [
        { guid: 'summary-1', title: 'Summarized Article', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() },
        { guid: 'no-summary-1', title: 'No Summary Article', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
      ])
      const articles = articlesService.findByFeed(feedId)
      articleWithSummaryId = articles.find(a => a.title === 'Summarized Article')!.id
      articleWithoutSummaryId = articles.find(a => a.title === 'No Summary Article')!.id
      articlesService.saveAiResult(articleWithSummaryId, 'summarize', 'これは要約です')
    })

    it('summaryOnly=true でAI要約済み記事のみ返す', () => {
      const result = articlesService.findAll({ limit: 10, offset: 0, summaryOnly: true })
      expect(result).toHaveLength(1)
      expect(result[0].id).toBe(articleWithSummaryId)
    })

    it('summaryOnly=false で全記事を返す', () => {
      const result = articlesService.findAll({ limit: 10, offset: 0, summaryOnly: false })
      expect(result).toHaveLength(2)
    })
  })

  describe('お気に入り機能', () => {
    let articleId: number

    beforeEach(() => {
      articlesService.upsertMany(feedId, [
        { guid: 'fav-1', title: 'Article 1', link: 'https://example.com/1', summary: '', publishedAt: new Date().toISOString() },
        { guid: 'fav-2', title: 'Article 2', link: 'https://example.com/2', summary: '', publishedAt: new Date().toISOString() },
      ])
      articleId = articlesService.findByFeed(feedId)[0].id
    })

    it('記事をお気に入りに追加できる', () => {
      articlesService.markAsFavorite(articleId)
      const article = articlesService.findById(articleId)
      expect(article?.is_favorite).toBe(1)
    })

    it('記事のお気に入りを解除できる', () => {
      articlesService.markAsFavorite(articleId)
      articlesService.markAsUnfavorite(articleId)
      const article = articlesService.findById(articleId)
      expect(article?.is_favorite).toBe(0)
    })

    it('デフォルトは is_favorite=0 である', () => {
      const article = articlesService.findById(articleId)
      expect(article?.is_favorite).toBe(0)
    })

    it('favoriteOnly=true でお気に入り記事のみ返す', () => {
      const articles = articlesService.findByFeed(feedId)
      articlesService.markAsFavorite(articles[0].id)

      const result = articlesService.findAll({ limit: 10, offset: 0, favoriteOnly: true })
      expect(result).toHaveLength(1)
      expect(result[0].id).toBe(articles[0].id)
    })

    it('favoriteOnly=false で全記事を返す', () => {
      const articles = articlesService.findByFeed(feedId)
      articlesService.markAsFavorite(articles[0].id)

      const result = articlesService.findAll({ limit: 10, offset: 0, favoriteOnly: false })
      expect(result).toHaveLength(2)
    })

    it('unreadOnly と favoriteOnly を同時に使える', () => {
      const articles = articlesService.findByFeed(feedId)
      articlesService.markAsFavorite(articles[0].id)
      articlesService.markAsRead(articles[0].id)
      // articles[1] はお気に入りではない・未読

      const result = articlesService.findAll({ limit: 10, offset: 0, favoriteOnly: true, unreadOnly: true })
      // お気に入りかつ未読は 0 件
      expect(result).toHaveLength(0)
    })

    it('お気に入り記事は保持期間を超えても削除しない', () => {
      const now = new Date()
      const old = new Date(now.getTime() - 200 * 24 * 60 * 60 * 1000) // 200日前

      articlesService.upsertMany(feedId, [
        { guid: 'old-fav', title: 'Old Favorite Article', link: 'https://example.com/old-fav', summary: '', publishedAt: old.toISOString() },
        { guid: 'old-normal', title: 'Old Normal Article', link: 'https://example.com/old-normal', summary: '', publishedAt: old.toISOString() },
      ])

      const allArticles = articlesService.findByFeed(feedId)
      const favoriteArticle = allArticles.find(a => a.title === 'Old Favorite Article')!
      articlesService.markAsFavorite(favoriteArticle.id)

      const threshold = new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000) // 半年前(180日)
      const deleted = articlesService.deleteOlderThan(threshold)

      expect(deleted).toBe(1) // お気に入りでない方のみ削除
      const remaining = articlesService.findByFeed(feedId)
      // beforeEach で追加した 2 件 + お気に入り 1 件 = 3 件中お気に入りのみ残る
      const oldFavArticle = remaining.find(a => a.title === 'Old Favorite Article')
      expect(oldFavArticle).toBeDefined()
      expect(oldFavArticle?.is_favorite).toBe(1)
    })

    it('published_at が null のお気に入り記事は保持期間を超えても削除しない', () => {
      // published_at なし（COALESCE で created_at を使う）のお気に入り記事
      articlesService.upsertMany(feedId, [
        { guid: 'no-date-fav', title: 'No Date Favorite', link: 'https://example.com/no-date-fav', summary: '' },
      ])

      const allArticles = articlesService.findByFeed(feedId)
      const noDateArticle = allArticles.find(a => a.title === 'No Date Favorite')!
      articlesService.markAsFavorite(noDateArticle.id)

      // 未来の threshold（created_at より後）でも、お気に入りは削除されない
      const futureThreshold = new Date(Date.now() + 1000)
      articlesService.deleteOlderThan(futureThreshold)

      // お気に入り記事が残っていることを確認
      const remaining = articlesService.findByFeed(feedId)
      const stillExists = remaining.find(a => a.title === 'No Date Favorite')
      expect(stillExists).toBeDefined()
      expect(stillExists?.is_favorite).toBe(1)
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
