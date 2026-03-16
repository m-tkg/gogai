import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { groupsApi, feedsApi, type Group, type Feed } from '../api/client'

interface SidebarProps {
  selectedFeedId: number | null
  selectedGroupId: number | null
  onSelectFeed: (id: number | null) => void
  onSelectGroup: (id: number | null) => void
  darkMode: boolean
  onToggleDark: () => void
  onOpenSettings: () => void
  showSettings: boolean
}

export function Sidebar({ selectedFeedId, selectedGroupId, onSelectFeed, onSelectGroup, darkMode, onToggleDark, onOpenSettings, showSettings }: SidebarProps) {
  const qc = useQueryClient()
  const [addFeedUrl, setAddFeedUrl] = useState('')
  const [addFeedGroupId, setAddFeedGroupId] = useState<number | undefined>()
  const [addGroupName, setAddGroupName] = useState('')
  const [showAddFeed, setShowAddFeed] = useState(false)
  const [showAddGroup, setShowAddGroup] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const { data: groups = [] } = useQuery({ queryKey: ['groups'], queryFn: groupsApi.list })
  const { data: feeds = [] } = useQuery({ queryKey: ['feeds'], queryFn: feedsApi.list })

  const addFeed = useMutation({
    mutationFn: () => feedsApi.create(addFeedUrl, addFeedGroupId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['feeds'] })
      qc.invalidateQueries({ queryKey: ['articles'] })
      setAddFeedUrl('')
      setAddFeedGroupId(undefined)
      setShowAddFeed(false)
      setError(null)
    },
    onError: (e: { response?: { data?: { error?: string } } }) => {
      setError(e.response?.data?.error ?? 'フィードの追加に失敗しました')
    },
  })

  const removeFeed = useMutation({
    mutationFn: (id: number) => feedsApi.remove(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['feeds'] }),
  })

  const addGroup = useMutation({
    mutationFn: () => groupsApi.create(addGroupName),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['groups'] })
      setAddGroupName('')
      setShowAddGroup(false)
    },
  })

  const removeGroup = useMutation({
    mutationFn: (id: number) => groupsApi.remove(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['groups'] }),
  })

  const feedsByGroup = (groupId: number | null) =>
    feeds.filter((f: Feed) => f.group_id === groupId)

  const ungroupedFeeds = feedsByGroup(null)

  return (
    <aside className="w-64 bg-gray-50 dark:bg-gray-900 border-r border-gray-200 dark:border-gray-700 flex flex-col h-screen overflow-y-auto flex-shrink-0">
      <div className="p-4 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
        <h1 className="text-xl font-bold text-gray-800 dark:text-gray-100">RSS Reader</h1>
        <div className="flex items-center gap-1">
          <button
            onClick={onOpenSettings}
            className={`p-1.5 rounded-md transition-colors ${
              showSettings
                ? 'bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-200'
                : 'text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
            }`}
            title="設定"
          >
            ⚙️
          </button>
          <button
            onClick={onToggleDark}
            className="p-1.5 rounded-md text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            title={darkMode ? 'ライトモードに切り替え' : 'ダークモードに切り替え'}
          >
            {darkMode ? '☀️' : '🌙'}
          </button>
        </div>
      </div>

      <nav className="flex-1 p-2">
        <button
          onClick={() => { onSelectFeed(null); onSelectGroup(null) }}
          className={`w-full text-left px-3 py-2 rounded-md text-sm mb-1 ${
            selectedFeedId === null && selectedGroupId === null
              ? 'bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300 font-medium'
              : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
          }`}
        >
          📋 すべての記事
        </button>

        {groups.map((group: Group) => (
          <div key={group.id} className="mb-1">
            <div className="flex items-center group/group">
              <button
                onClick={() => { onSelectGroup(group.id); onSelectFeed(null) }}
                className={`flex-1 text-left px-3 py-1.5 rounded-md text-sm font-medium ${
                  selectedGroupId === group.id
                    ? 'bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                }`}
              >
                📁 {group.name}
              </button>
              <button
                onClick={() => removeGroup.mutate(group.id)}
                className="hidden group-hover/group:block px-1 text-gray-400 hover:text-red-500 text-xs"
                title="グループを削除"
              >
                ✕
              </button>
            </div>
            {feedsByGroup(group.id).map((feed: Feed) => (
              <FeedItem
                key={feed.id}
                feed={feed}
                selected={selectedFeedId === feed.id}
                onSelect={() => { onSelectFeed(feed.id); onSelectGroup(null) }}
                onRemove={() => removeFeed.mutate(feed.id)}
              />
            ))}
          </div>
        ))}

        {ungroupedFeeds.length > 0 && (
          <div className="mt-2">
            <p className="text-xs text-gray-400 dark:text-gray-500 px-3 mb-1">グループなし</p>
            {ungroupedFeeds.map((feed: Feed) => (
              <FeedItem
                key={feed.id}
                feed={feed}
                selected={selectedFeedId === feed.id}
                onSelect={() => { onSelectFeed(feed.id); onSelectGroup(null) }}
                onRemove={() => removeFeed.mutate(feed.id)}
              />
            ))}
          </div>
        )}
      </nav>

      {error && (
        <div className="mx-2 mb-2 p-2 bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-700 rounded text-xs text-red-600 dark:text-red-400">
          {error}
          <button onClick={() => setError(null)} className="ml-1 font-bold">✕</button>
        </div>
      )}

      <div className="p-2 border-t border-gray-200 dark:border-gray-700">
        {showAddFeed ? (
          <div className="space-y-1">
            <input
              type="url"
              placeholder="Feed URL"
              value={addFeedUrl}
              onChange={e => setAddFeedUrl(e.target.value)}
              className="w-full px-2 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none focus:border-blue-400 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500"
            />
            <select
              value={addFeedGroupId ?? ''}
              onChange={e => setAddFeedGroupId(e.target.value ? Number(e.target.value) : undefined)}
              className="w-full px-2 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
            >
              <option value="">グループなし</option>
              {groups.map((g: Group) => <option key={g.id} value={g.id}>{g.name}</option>)}
            </select>
            <div className="flex gap-1">
              <button
                onClick={() => addFeed.mutate()}
                disabled={!addFeedUrl || addFeed.isPending}
                className="flex-1 px-2 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
              >
                {addFeed.isPending ? '追加中...' : '追加'}
              </button>
              <button
                onClick={() => { setShowAddFeed(false); setError(null) }}
                className="px-2 py-1 text-xs border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300"
              >
                キャンセル
              </button>
            </div>
          </div>
        ) : (
          <button
            onClick={() => setShowAddFeed(true)}
            className="w-full px-3 py-1.5 text-sm text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-md text-left"
          >
            ＋ フィードを追加
          </button>
        )}

        {showAddGroup ? (
          <div className="mt-1 space-y-1">
            <input
              type="text"
              placeholder="グループ名"
              value={addGroupName}
              onChange={e => setAddGroupName(e.target.value)}
              className="w-full px-2 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none focus:border-blue-400 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500"
            />
            <div className="flex gap-1">
              <button
                onClick={() => addGroup.mutate()}
                disabled={!addGroupName || addGroup.isPending}
                className="flex-1 px-2 py-1 text-xs bg-green-500 text-white rounded hover:bg-green-600 disabled:opacity-50"
              >
                作成
              </button>
              <button
                onClick={() => setShowAddGroup(false)}
                className="px-2 py-1 text-xs border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300"
              >
                キャンセル
              </button>
            </div>
          </div>
        ) : (
          <button
            onClick={() => setShowAddGroup(true)}
            className="w-full px-3 py-1.5 text-sm text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-md text-left mt-1"
          >
            ＋ グループを追加
          </button>
        )}
      </div>
    </aside>
  )
}

function FeedItem({ feed, selected, onSelect, onRemove }: {
  feed: Feed
  selected: boolean
  onSelect: () => void
  onRemove: () => void
}) {
  return (
    <div className="flex items-center group/feed pl-3">
      <button
        onClick={onSelect}
        className={`flex-1 flex items-center gap-2 px-2 py-1.5 rounded-md text-sm ${
          selected
            ? 'bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300'
            : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
        }`}
      >
        <FeedFavicon url={feed.favicon_url} />
        <span className="truncate">{feed.title ?? feed.url}</span>
      </button>
      <button
        onClick={onRemove}
        className="hidden group-hover/feed:block px-1 text-gray-400 hover:text-red-500 text-xs"
        title="フィードを削除"
      >
        ✕
      </button>
    </div>
  )
}

function FeedFavicon({ url }: { url: string | null }) {
  if (!url) return <span className="text-xs">📰</span>
  return (
    <img
      src={url}
      alt=""
      className="w-4 h-4 object-contain"
      onError={e => { (e.target as HTMLImageElement).style.display = 'none' }}
    />
  )
}
