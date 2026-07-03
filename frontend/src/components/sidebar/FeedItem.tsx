import { useState } from 'react'
import type { Group, Feed } from '../../api/client'
import { confirmCancelBtn, inputXs, selectXs, secondaryBtnXs } from '../ui/formStyles'

export interface FeedItemProps {
  feed: Feed
  groups: Group[]
  selected: boolean
  onSelect: () => void
  onRemove: (onSuccess: () => void) => void
  onRefresh: () => void
  onUpdate: (data: { url?: string; groupId?: number | null }, onSuccess: () => void, onError: () => void) => void
  isRefreshing: boolean
  isUpdating: boolean
  isDragging?: boolean
  isDragOver?: boolean
  onDragStart?: () => void
  onDragOver?: (e: React.DragEvent) => void
  onDrop?: () => void
  onDragEnd?: () => void
}

export function FeedItem({ feed, groups, selected, onSelect, onRemove, onRefresh, onUpdate, isRefreshing, isUpdating, isDragging, isDragOver, onDragStart, onDragOver, onDrop, onDragEnd }: FeedItemProps) {
  const [isEditing, setIsEditing] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [editUrl, setEditUrl] = useState(feed.url)
  const [editGroupId, setEditGroupId] = useState<number | null>(feed.group_id)
  const [editError, setEditError] = useState<string | null>(null)

  const handleSave = () => {
    setEditError(null)
    onUpdate(
      { url: editUrl.trim() || feed.url, groupId: editGroupId },
      () => setIsEditing(false),
      () => setEditError('保存に失敗しました。URLを確認してください。'),
    )
  }

  const handleCancel = () => {
    setEditUrl(feed.url)
    setEditGroupId(feed.group_id)
    setEditError(null)
    setIsEditing(false)
  }

  if (isEditing) {
    return (
      <div className="pl-3 pr-1 py-1 space-y-1">
        <input
          type="url"
          value={editUrl}
          onChange={e => setEditUrl(e.target.value)}
          className={inputXs}
          placeholder="Feed URL"
        />
        <select
          value={editGroupId ?? ''}
          onChange={e => setEditGroupId(e.target.value ? Number(e.target.value) : null)}
          className={selectXs}
        >
          <option value="">グループなし</option>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        {editError && (
          <p className="text-xs text-red-500 dark:text-red-400">{editError}</p>
        )}
        <div className="flex gap-1">
          <button
            onClick={handleSave}
            disabled={isUpdating}
            className="flex-1 px-2 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
          >
            {isUpdating ? '保存中…' : '保存'}
          </button>
          <button
            onClick={handleCancel}
            disabled={isUpdating}
            className={`${secondaryBtnXs} disabled:opacity-50`}
          >
            キャンセル
          </button>
        </div>
      </div>
    )
  }

  return (
    <div
      className={`flex items-center group/feed pl-3 ${isDragOver ? 'border-t-2 border-blue-400' : ''} ${isDragging ? 'opacity-40' : ''}`}
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      onDragEnd={onDragEnd}
    >
      <span
        className="hidden group-hover/feed:flex cursor-grab text-gray-300 dark:text-gray-600 text-xs px-0.5 select-none"
        title="ドラッグして並び替え"
      >
        ⠿
      </span>
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
      {confirmDelete ? (
        <div className="flex items-center gap-1 px-1">
          <span className="text-xs text-red-500 dark:text-red-400">削除?</span>
          <button
            onClick={() => onRemove(() => setConfirmDelete(false))}
            className="px-1.5 py-0.5 text-xs bg-red-500 text-white rounded hover:bg-red-600"
          >
            削除
          </button>
          <button
            onClick={() => setConfirmDelete(false)}
            className={confirmCancelBtn}
          >
            キャンセル
          </button>
        </div>
      ) : (
        <>
          <button
            onClick={onRefresh}
            disabled={isRefreshing}
            className="hidden group-hover/feed:block px-1 text-gray-400 hover:text-blue-500 text-xs disabled:opacity-50"
            title="フィードを更新"
          >
            {isRefreshing ? '…' : '↻'}
          </button>
          <button
            onClick={() => setIsEditing(true)}
            className="hidden group-hover/feed:block px-1 text-gray-400 hover:text-green-500 text-xs"
            title="フィードを編集"
            aria-label="フィードを編集"
          >
            ✎
          </button>
          <button
            onClick={() => setConfirmDelete(true)}
            className="hidden group-hover/feed:block px-1 text-gray-400 hover:text-red-500 text-xs"
            title="フィードを削除"
            aria-label="フィードを削除"
          >
            ✕
          </button>
        </>
      )}
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
