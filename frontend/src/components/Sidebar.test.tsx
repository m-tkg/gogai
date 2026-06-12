import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sidebar } from './Sidebar'
import type { Group, Feed } from '../api/client'

vi.mock('../api/client', () => ({
  groupsApi: {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    refresh: vi.fn(),
    reorder: vi.fn(),
  },
  feedsApi: {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    refresh: vi.fn(),
    refreshAll: vi.fn(),
    reorder: vi.fn(),
  },
}))

import { groupsApi, feedsApi } from '../api/client'

const groupsList = vi.mocked(groupsApi.list)
const feedsList = vi.mocked(feedsApi.list)
const feedsCreate = vi.mocked(feedsApi.create)

function makeGroup(over: Partial<Group> = {}): Group {
  return { id: 1, name: 'Tech', is_secret: 0, created_at: '', display_order: 0, ...over }
}

function makeFeed(over: Partial<Feed> = {}): Feed {
  return {
    id: 1, url: 'https://example.com/feed.xml', title: 'Example Feed',
    favicon_url: null, group_id: null, last_fetched_at: null, created_at: '', display_order: 0,
    ...over,
  }
}

function renderSidebar(props: Partial<Parameters<typeof Sidebar>[0]> = {}) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const defaultProps = {
    selectedFeedId: null,
    selectedGroupId: null,
    onSelectFeed: vi.fn(),
    onSelectGroup: vi.fn(),
    darkMode: false,
    onToggleDark: vi.fn(),
    onOpenSettings: vi.fn(),
    showSettings: false,
    isOpen: true,
    onToggle: vi.fn(),
    showSecretGroups: false,
  }
  const merged = { ...defaultProps, ...props }
  render(
    <QueryClientProvider client={qc}>
      <Sidebar {...merged} />
    </QueryClientProvider>
  )
  return merged
}

beforeEach(() => {
  vi.clearAllMocks()
  groupsList.mockResolvedValue([])
  feedsList.mockResolvedValue([])
})

describe('Sidebar（特性テスト）', () => {
  it('グループとグループ内フィードを表示する', async () => {
    groupsList.mockResolvedValue([makeGroup({ id: 1, name: 'Tech' })])
    feedsList.mockResolvedValue([makeFeed({ id: 10, title: 'Example Feed', group_id: 1 })])
    renderSidebar()

    expect(await screen.findByText('Tech')).toBeInTheDocument()
    expect(await screen.findByText('Example Feed')).toBeInTheDocument()
  })

  it('グループなしフィードは「グループなし」セクションに表示する', async () => {
    feedsList.mockResolvedValue([makeFeed({ id: 10, title: 'Solo Feed', group_id: null })])
    renderSidebar()

    expect(await screen.findByText('グループなし')).toBeInTheDocument()
    expect(await screen.findByText('Solo Feed')).toBeInTheDocument()
  })

  it('シークレットグループは showSecretGroups=false では表示しない', async () => {
    groupsList.mockResolvedValue([
      makeGroup({ id: 1, name: 'Public' }),
      makeGroup({ id: 2, name: 'Secret', is_secret: 1 }),
    ])
    renderSidebar({ showSecretGroups: false })

    expect(await screen.findByText('Public')).toBeInTheDocument()
    expect(screen.queryByText('Secret')).not.toBeInTheDocument()
  })

  it('シークレットグループは showSecretGroups=true なら表示する', async () => {
    groupsList.mockResolvedValue([makeGroup({ id: 2, name: 'Secret', is_secret: 1 })])
    renderSidebar({ showSecretGroups: true })

    expect(await screen.findByText('Secret')).toBeInTheDocument()
  })

  it('フィードをクリックすると onSelectFeed が呼ばれ、グループ選択は解除される', async () => {
    feedsList.mockResolvedValue([makeFeed({ id: 10, title: 'Solo Feed' })])
    const { onSelectFeed, onSelectGroup } = renderSidebar()

    await userEvent.click(await screen.findByText('Solo Feed'))
    expect(onSelectFeed).toHaveBeenCalledWith(10)
    expect(onSelectGroup).toHaveBeenCalledWith(null)
  })

  it('グループ名をクリックすると onSelectGroup が呼ばれる', async () => {
    groupsList.mockResolvedValue([makeGroup({ id: 1, name: 'Tech' })])
    const { onSelectGroup, onSelectFeed } = renderSidebar()

    await userEvent.click(await screen.findByText('Tech'))
    expect(onSelectGroup).toHaveBeenCalledWith(1)
    expect(onSelectFeed).toHaveBeenCalledWith(null)
  })

  it('フィード追加: URL を入力して追加すると feedsApi.create が呼ばれフォームが閉じる', async () => {
    feedsCreate.mockResolvedValue(makeFeed())
    renderSidebar()

    await userEvent.click(screen.getByText('＋ フィードを追加'))
    await userEvent.type(screen.getByPlaceholderText('Feed URL'), 'https://example.com')
    await userEvent.click(screen.getByText('追加'))

    await waitFor(() => {
      expect(feedsCreate).toHaveBeenCalledWith('https://example.com', undefined)
    })
    await waitFor(() => {
      expect(screen.queryByPlaceholderText('Feed URL')).not.toBeInTheDocument()
    })
  })

  it('フィード追加失敗: レスポンスの { error } メッセージを表示する', async () => {
    feedsCreate.mockRejectedValue({ response: { data: { error: 'RSSフィードが見つかりませんでした' } } })
    renderSidebar()

    await userEvent.click(screen.getByText('＋ フィードを追加'))
    await userEvent.type(screen.getByPlaceholderText('Feed URL'), 'https://bad.example.com')
    await userEvent.click(screen.getByText('追加'))

    expect(await screen.findByText('RSSフィードが見つかりませんでした')).toBeInTheDocument()
  })

  it('グループ追加: 名前を入力して作成すると groupsApi.create が呼ばれる', async () => {
    const groupsCreate = vi.mocked(groupsApi.create)
    groupsCreate.mockResolvedValue(makeGroup({ name: 'News' }))
    renderSidebar()

    await userEvent.click(screen.getByText('＋ グループを追加'))
    await userEvent.type(screen.getByPlaceholderText('グループ名'), 'News')
    await userEvent.click(screen.getByText('作成'))

    await waitFor(() => {
      expect(groupsCreate).toHaveBeenCalledWith('News')
    })
  })

  it('フォルダアイコンでグループを折りたたむとフィードが非表示になる', async () => {
    groupsList.mockResolvedValue([makeGroup({ id: 1, name: 'Tech' })])
    feedsList.mockResolvedValue([makeFeed({ id: 10, title: 'Example Feed', group_id: 1 })])
    renderSidebar()

    expect(await screen.findByText('Example Feed')).toBeInTheDocument()
    await userEvent.click(screen.getByTitle('折りたたむ'))
    expect(screen.queryByText('Example Feed')).not.toBeInTheDocument()
  })

  it('isOpen=false ではサイドバー本体を表示せず開くボタンのみ表示する', () => {
    renderSidebar({ isOpen: false })
    expect(screen.getByLabelText('サイドバーを開く')).toBeInTheDocument()
    expect(screen.queryByText('＋ フィードを追加')).not.toBeInTheDocument()
  })

  it('グループ削除は確認 UI を経由して groupsApi.remove を呼ぶ', async () => {
    const groupsRemove = vi.mocked(groupsApi.remove)
    groupsRemove.mockResolvedValue({} as never)
    groupsList.mockResolvedValue([makeGroup({ id: 1, name: 'Tech' })])
    renderSidebar()

    await screen.findByText('Tech')
    await userEvent.click(screen.getByLabelText('グループを削除'))
    expect(screen.getByText('削除?')).toBeInTheDocument()
    await userEvent.click(screen.getByText('削除'))

    await waitFor(() => {
      expect(groupsRemove).toHaveBeenCalledWith(1)
    })
  })
})
