import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { initSchema } from '../db/schema.js'
import { FeedsService } from '../services/feeds.js'
import { GroupsService } from '../services/groups.js'

let db: Database.Database
let feedsService: FeedsService
let groupsService: GroupsService

beforeEach(() => {
  db = new Database(':memory:')
  db.pragma('foreign_keys = ON')
  initSchema(db)
  feedsService = new FeedsService(db)
  groupsService = new GroupsService(db)
})

afterEach(() => {
  db.close()
})

describe('FeedsService', () => {
  it('フィードを追加できる', () => {
    const feed = feedsService.create({ url: 'https://example.com/feed.xml', title: 'Example' })
    expect(feed.id).toBeTypeOf('number')
    expect(feed.url).toBe('https://example.com/feed.xml')
    expect(feed.title).toBe('Example')
  })

  it('全フィードを取得できる', () => {
    feedsService.create({ url: 'https://a.com/feed.xml' })
    feedsService.create({ url: 'https://b.com/feed.xml' })
    expect(feedsService.findAll()).toHaveLength(2)
  })

  it('IDでフィードを取得できる', () => {
    const feed = feedsService.create({ url: 'https://example.com/feed.xml' })
    expect(feedsService.findById(feed.id)?.url).toBe('https://example.com/feed.xml')
  })

  it('グループにフィードを割り当てられる', () => {
    const group = groupsService.create('Tech')
    const feed = feedsService.create({ url: 'https://example.com/feed.xml', groupId: group.id })
    expect(feed.group_id).toBe(group.id)
  })

  it('フィードのグループを変更できる', () => {
    const g1 = groupsService.create('Tech')
    const g2 = groupsService.create('News')
    const feed = feedsService.create({ url: 'https://example.com/feed.xml', groupId: g1.id })
    const updated = feedsService.update(feed.id, { groupId: g2.id })
    expect(updated?.group_id).toBe(g2.id)
  })

  it('フィードを削除できる', () => {
    const feed = feedsService.create({ url: 'https://example.com/feed.xml' })
    feedsService.remove(feed.id)
    expect(feedsService.findById(feed.id)).toBeNull()
  })

  it('同じURLのフィードは追加できない', () => {
    feedsService.create({ url: 'https://example.com/feed.xml' })
    expect(() => feedsService.create({ url: 'https://example.com/feed.xml' })).toThrow()
  })
})
