import { useState } from 'react'
import type { Group } from '../../api/client'
import { getApiErrorMessage } from '../../api/errors'
import type { FeedMutations } from './FeedList'
import type { GroupMutations } from './GroupSection'

// フィード追加フォーム（開閉・入力・エラー表示を自己管理する）
export function AddFeedForm({ groups, feedMutations }: { groups: Group[]; feedMutations: FeedMutations }) {
  const [open, setOpen] = useState(false)
  const [url, setUrl] = useState('')
  const [groupId, setGroupId] = useState<number | undefined>()
  const [error, setError] = useState<string | null>(null)
  const { addFeed } = feedMutations

  const submit = () => {
    addFeed.mutate({ url, groupId }, {
      onSuccess: () => {
        setUrl('')
        setGroupId(undefined)
        setOpen(false)
        setError(null)
      },
      onError: (e) => {
        setError(getApiErrorMessage(e, 'フィードの追加に失敗しました'))
      },
    })
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="w-full px-3 py-1.5 text-sm text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-md text-left"
      >
        ＋ フィードを追加
      </button>
    )
  }

  return (
    <div className="space-y-1">
      {error && (
        <div className="p-2 bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-700 rounded text-xs text-red-600 dark:text-red-400">
          {error}
          <button onClick={() => setError(null)} className="ml-1 font-bold">✕</button>
        </div>
      )}
      <input
        type="url"
        placeholder="Feed URL"
        value={url}
        onChange={e => setUrl(e.target.value)}
        className="w-full px-2 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none focus:border-blue-400 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500"
      />
      <select
        value={groupId ?? ''}
        onChange={e => setGroupId(e.target.value ? Number(e.target.value) : undefined)}
        className="w-full px-2 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
      >
        <option value="">グループなし</option>
        {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
      </select>
      <div className="flex gap-1">
        <button
          onClick={submit}
          disabled={!url || addFeed.isPending}
          className="flex-1 px-2 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
        >
          {addFeed.isPending ? '追加中...' : '追加'}
        </button>
        <button
          onClick={() => { setOpen(false); setError(null) }}
          className="px-2 py-1 text-xs border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300"
        >
          キャンセル
        </button>
      </div>
    </div>
  )
}

// グループ追加フォーム
export function AddGroupForm({ groupMutations }: { groupMutations: GroupMutations }) {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const { addGroup } = groupMutations

  const submit = () => {
    addGroup.mutate(name, {
      onSuccess: () => {
        setName('')
        setOpen(false)
      },
    })
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="w-full px-3 py-1.5 text-sm text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-md text-left mt-1"
      >
        ＋ グループを追加
      </button>
    )
  }

  return (
    <div className="mt-1 space-y-1">
      <input
        type="text"
        placeholder="グループ名"
        value={name}
        onChange={e => setName(e.target.value)}
        className="w-full px-2 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none focus:border-blue-400 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-500"
      />
      <div className="flex gap-1">
        <button
          onClick={submit}
          disabled={!name || addGroup.isPending}
          className="flex-1 px-2 py-1 text-xs bg-green-500 text-white rounded hover:bg-green-600 disabled:opacity-50"
        >
          作成
        </button>
        <button
          onClick={() => setOpen(false)}
          className="px-2 py-1 text-xs border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300"
        >
          キャンセル
        </button>
      </div>
    </div>
  )
}
