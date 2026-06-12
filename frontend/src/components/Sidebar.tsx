import { useState, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { groupsApi, feedsApi, type Group, type Feed } from '../api/client'
import { queryKeys } from '../api/queryKeys'
import { useFeedMutations } from '../hooks/useFeedMutations'
import { useGroupMutations } from '../hooks/useGroupMutations'
import { useDragReorder } from '../hooks/useDragReorder'
import { GroupSection } from './sidebar/GroupSection'
import { FeedList } from './sidebar/FeedList'
import { AddFeedForm, AddGroupForm } from './sidebar/AddForms'

interface SidebarProps {
  selectedFeedId: number | null
  selectedGroupId: number | null
  onSelectFeed: (id: number | null) => void
  onSelectGroup: (id: number | null) => void
  darkMode: boolean
  onToggleDark: () => void
  onOpenSettings: () => void
  showSettings: boolean
  isOpen: boolean
  onToggle: () => void
  showSecretGroups: boolean
}

export function Sidebar({ selectedFeedId, selectedGroupId, onSelectFeed, onSelectGroup, darkMode, onToggleDark, onOpenSettings, showSettings, isOpen, onToggle, showSecretGroups }: SidebarProps) {
  const [collapsedGroupIds, setCollapsedGroupIds] = useState<Set<number>>(new Set())

  const { data: groups = [] } = useQuery({ queryKey: queryKeys.groups, queryFn: groupsApi.list })
  const { data: feeds = [] } = useQuery({ queryKey: queryKeys.feeds, queryFn: feedsApi.list })

  const feedMutations = useFeedMutations()
  const groupMutations = useGroupMutations()
  const feedDnd = useDragReorder<Feed>((ids) => feedMutations.reorderFeeds.mutate(ids))
  const groupDnd = useDragReorder<Group>((ids) => groupMutations.reorderGroups.mutate(ids))

  const isExpanded = (id: number) => !collapsedGroupIds.has(id)
  const toggleExpanded = (id: number) => {
    setCollapsedGroupIds(prev => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  // モバイルでオーバーレイ表示中に Escape キーで閉じる
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen && window.matchMedia('(max-width: 767px)').matches) {
        onToggle()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, onToggle])

  // モバイルではナビ項目選択後にサイドバーを閉じる（open 状態のときのみ）
  const closeSidebarIfMobile = () => {
    if (window.matchMedia('(max-width: 767px)').matches && isOpen) {
      onToggle()
    }
  }

  const selectFeed = (id: number) => {
    onSelectFeed(id)
    onSelectGroup(null)
    closeSidebarIfMobile()
  }

  const feedsByGroup = (groupId: number | null) =>
    feeds.filter((f: Feed) => f.group_id === groupId)

  const ungroupedFeeds = feedsByGroup(null)
  const visibleGroups = groups.filter((g: Group) => g.is_secret !== 1 || showSecretGroups)

  // useQuery はサイドバーが閉じていても実行し続ける（5分ごとの自動更新を維持するため意図的）
  if (!isOpen) {
    return (
      // モバイル: 完全非表示 / デスクトップ: w-10 の折りたたみ帯を表示
      <aside className="hidden md:flex w-10 bg-gray-50 dark:bg-gray-900 border-r border-gray-200 dark:border-gray-700 flex-col h-screen flex-shrink-0 items-center pt-3">
        <button
          onClick={onToggle}
          className="p-1.5 rounded-md text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
          title="サイドバーを開く"
          aria-label="サイドバーを開く"
        >
          ▶
        </button>
      </aside>
    )
  }

  return (
    <>
      {/* モバイル用バックドロップ（サイドバー背面のオーバーレイ） */}
      <div
        className="fixed inset-0 z-40 bg-black/40 md:hidden"
        onClick={onToggle}
        aria-hidden="true"
      />
      {/* サイドバー本体: モバイル=固定位置オーバーレイ / デスクトップ=通常フロー */}
    <aside className="fixed md:static inset-y-0 left-0 z-50 md:z-auto w-64 bg-gray-50 dark:bg-gray-900 border-r border-gray-200 dark:border-gray-700 flex flex-col h-screen overflow-y-auto flex-shrink-0">
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
          <button
            onClick={onToggle}
            className="p-1.5 rounded-md text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            title="サイドバーを閉じる"
            aria-label="サイドバーを閉じる"
          >
            ◀
          </button>
        </div>
      </div>

      <nav className="flex-1 p-2">
        <div className="flex items-center group/all mb-1">
          <button
            onClick={() => { onSelectFeed(null); onSelectGroup(null); closeSidebarIfMobile() }}
            className={`flex-1 text-left px-3 py-2 rounded-md text-sm ${
              selectedFeedId === null && selectedGroupId === null
                ? 'bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300 font-medium'
                : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
            }`}
          >
            📋 すべての記事
          </button>
          <button
            onClick={() => feedMutations.refreshAllFeeds.mutate()}
            disabled={feedMutations.refreshAllFeeds.isPending}
            className="hidden group-hover/all:block px-1 text-gray-400 hover:text-blue-500 text-xs disabled:opacity-50"
            title="全フィードを更新"
          >
            {feedMutations.refreshAllFeeds.isPending ? '…' : '↻'}
          </button>
        </div>

        {visibleGroups.map((group: Group) => (
          <GroupSection
            key={group.id}
            group={group}
            groupFeeds={feedsByGroup(group.id)}
            groups={groups}
            selected={selectedGroupId === group.id}
            selectedFeedId={selectedFeedId}
            onSelectGroup={() => { onSelectGroup(group.id); onSelectFeed(null); closeSidebarIfMobile() }}
            onSelectFeed={selectFeed}
            isExpanded={isExpanded(group.id)}
            onToggleExpanded={() => toggleExpanded(group.id)}
            groupMutations={groupMutations}
            feedMutations={feedMutations}
            feedDnd={feedDnd}
            isDragging={groupDnd.dragId === group.id}
            isDragOver={groupDnd.dragOverId === group.id}
            onDragStart={() => groupDnd.handleDragStart(group.id)}
            onDragOver={(e) => groupDnd.handleDragOver(e, group.id)}
            onDrop={() => groupDnd.handleDrop(visibleGroups)}
            onDragEnd={groupDnd.handleDragEnd}
          />
        ))}

        {ungroupedFeeds.length > 0 && (
          <div className="mt-2">
            <p className="text-xs text-gray-400 dark:text-gray-500 px-3 mb-1">グループなし</p>
            <FeedList
              feeds={ungroupedFeeds}
              groups={groups}
              selectedFeedId={selectedFeedId}
              onSelectFeed={selectFeed}
              feedMutations={feedMutations}
              feedDnd={feedDnd}
            />
          </div>
        )}
      </nav>

      <div className="p-2 border-t border-gray-200 dark:border-gray-700">
        <AddFeedForm groups={groups} feedMutations={feedMutations} />
        <AddGroupForm groupMutations={groupMutations} />
      </div>
    </aside>
    </>
  )
}
