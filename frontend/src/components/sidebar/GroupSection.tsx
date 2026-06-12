import { useState } from 'react'
import type { Group, Feed } from '../../api/client'
import type { useGroupMutations } from '../../hooks/useGroupMutations'
import { FeedList, type FeedMutations, type DragReorder } from './FeedList'

export type GroupMutations = ReturnType<typeof useGroupMutations>

interface GroupSectionProps {
  group: Group
  groupFeeds: Feed[]
  groups: Group[]
  selected: boolean
  selectedFeedId: number | null
  onSelectGroup: () => void
  onSelectFeed: (id: number) => void
  isExpanded: boolean
  onToggleExpanded: () => void
  groupMutations: GroupMutations
  feedMutations: FeedMutations
  feedDnd: DragReorder
  isDragging: boolean
  isDragOver: boolean
  onDragStart: () => void
  onDragOver: (e: React.DragEvent) => void
  onDrop: () => void
  onDragEnd: () => void
}

// グループ見出し行 + 配下のフィード一覧
export function GroupSection({
  group, groupFeeds, groups, selected, selectedFeedId,
  onSelectGroup, onSelectFeed, isExpanded, onToggleExpanded,
  groupMutations, feedMutations, feedDnd,
  isDragging, isDragOver, onDragStart, onDragOver, onDrop, onDragEnd,
}: GroupSectionProps) {
  const [confirmDelete, setConfirmDelete] = useState(false)
  const { removeGroup, refreshGroup, toggleGroupSecret } = groupMutations

  return (
    <div
      className={`mb-1 ${isDragOver ? 'border-t-2 border-blue-400' : ''} ${isDragging ? 'opacity-40' : ''}`}
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      onDragEnd={onDragEnd}
    >
      <div className="flex items-center group/group">
        {/* ドラッグハンドル */}
        <span
          className="hidden group-hover/group:flex cursor-grab text-gray-300 dark:text-gray-600 text-xs px-0.5 select-none"
          title="ドラッグして並び替え"
        >
          ⠿
        </span>
        {/* フォルダアイコン: クリックで展開・折りたたみ */}
        <button
          onClick={onToggleExpanded}
          className="px-2 py-1.5 text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 text-sm flex items-center gap-0.5"
          title={isExpanded ? '折りたたむ' : '展開する'}
        >
          <span>{group.is_secret === 1 ? '🔒' : '📁'}</span>
          <span className="text-xs">{isExpanded ? '▾' : '▸'}</span>
        </button>
        {/* グループ名: クリックでグループ記事一覧へ */}
        <button
          onClick={() => { onSelectGroup(); setConfirmDelete(false) }}
          className={`flex-1 text-left px-2 py-1.5 rounded-md text-sm font-medium ${
            selected
              ? 'bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300'
              : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
          }`}
        >
          {group.name}
        </button>
        {confirmDelete ? (
          <div className="flex items-center gap-1 px-1">
            <span className="text-xs text-red-500 dark:text-red-400">削除?</span>
            <button
              onClick={() => removeGroup.mutate(group.id, { onSuccess: () => setConfirmDelete(false) })}
              className="px-1.5 py-0.5 text-xs bg-red-500 text-white rounded hover:bg-red-600"
            >
              削除
            </button>
            <button
              onClick={() => setConfirmDelete(false)}
              className="px-1.5 py-0.5 text-xs border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300"
            >
              キャンセル
            </button>
          </div>
        ) : (
          <>
            <button
              onClick={() => refreshGroup.mutate(group.id)}
              disabled={refreshGroup.isPending && refreshGroup.variables === group.id}
              className="hidden group-hover/group:block px-1 text-gray-400 hover:text-blue-500 text-xs disabled:opacity-50"
              title="グループのフィードを更新"
            >
              {refreshGroup.isPending && refreshGroup.variables === group.id ? '…' : '↻'}
            </button>
            <button
              onClick={() => toggleGroupSecret.mutate({ id: group.id, name: group.name, isSecret: group.is_secret === 1 ? 0 : 1 })}
              className="hidden group-hover/group:block px-1 text-gray-400 hover:text-yellow-500 text-xs"
              title={group.is_secret === 1 ? 'シークレットを解除' : 'シークレットに設定'}
            >
              {group.is_secret === 1 ? '🔓' : '🔒'}
            </button>
            <button
              onClick={() => setConfirmDelete(true)}
              className="hidden group-hover/group:block px-1 text-gray-400 hover:text-red-500 text-xs"
              title="グループを削除"
              aria-label="グループを削除"
            >
              ✕
            </button>
          </>
        )}
      </div>
      {isExpanded && (
        <FeedList
          feeds={groupFeeds}
          groups={groups}
          selectedFeedId={selectedFeedId}
          onSelectFeed={onSelectFeed}
          feedMutations={feedMutations}
          feedDnd={feedDnd}
        />
      )}
    </div>
  )
}
