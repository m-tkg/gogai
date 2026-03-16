import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { articlesApi, feedsApi, type Article } from '../api/client'
import { useState } from 'react'

interface ArticleListProps {
  feedId: number | null
  groupId: number | null
  onSelectArticle: (article: Article) => void
  selectedArticleId: number | null
}

export function ArticleList({ feedId, groupId, onSelectArticle, selectedArticleId }: ArticleListProps) {
  const qc = useQueryClient()
  const [unreadOnly, setUnreadOnly] = useState(false)

  const { data: articles = [], isLoading } = useQuery({
    queryKey: ['articles', { feedId, groupId, unreadOnly }],
    queryFn: () => articlesApi.list({ feedId: feedId ?? undefined, groupId: groupId ?? undefined, unreadOnly, limit: 100, offset: 0 }),
  })

  const refresh = useMutation({
    mutationFn: () => feedsApi.refresh(feedId!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['articles'] })
      qc.invalidateQueries({ queryKey: ['feeds'] })
    },
  })

  const markAsRead = useMutation({
    mutationFn: (id: number) => articlesApi.markAsRead(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['articles'] }),
  })

  const markAsUnread = useMutation({
    mutationFn: (id: number) => articlesApi.markAsUnread(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['articles'] }),
  })

  const handleSelect = (article: Article) => {
    onSelectArticle(article)
    if (!article.is_read) {
      markAsRead.mutate(article.id)
    }
  }

  return (
    <div className="flex flex-col h-screen overflow-hidden">
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-white">
        <label className="flex items-center gap-2 text-sm text-gray-600 cursor-pointer">
          <input
            type="checkbox"
            checked={unreadOnly}
            onChange={e => setUnreadOnly(e.target.checked)}
            className="rounded"
          />
          未読のみ
        </label>
        {feedId && (
          <button
            onClick={() => refresh.mutate()}
            disabled={refresh.isPending}
            className="text-sm text-blue-600 hover:text-blue-800 disabled:opacity-50"
          >
            {refresh.isPending ? '更新中...' : '↻ 更新'}
          </button>
        )}
      </div>

      <div className="flex-1 overflow-y-auto">
        {isLoading && (
          <div className="flex items-center justify-center h-32 text-gray-400">
            読み込み中...
          </div>
        )}
        {!isLoading && articles.length === 0 && (
          <div className="flex items-center justify-center h-32 text-gray-400 text-sm">
            記事がありません
          </div>
        )}
        {articles.map((article: Article) => (
          <ArticleCard
            key={article.id}
            article={article}
            selected={selectedArticleId === article.id}
            onClick={() => handleSelect(article)}
            onMarkAsUnread={() => markAsUnread.mutate(article.id)}
          />
        ))}
      </div>
    </div>
  )
}

function ArticleCard({ article, selected, onClick, onMarkAsUnread }: {
  article: Article
  selected: boolean
  onClick: () => void
  onMarkAsUnread: () => void
}) {
  const [claudeOutput, setClaudeOutput] = useState<{ action: 'summarize' | 'translate'; text: string } | null>(null)
  const [pendingAction, setPendingAction] = useState<'summarize' | 'translate' | null>(null)

  const claudeMutation = useMutation({
    mutationFn: (action: 'summarize' | 'translate') => articlesApi.claude(article.id, action),
    onSuccess: (data, action) => {
      setClaudeOutput({ action, text: data.output })
      setPendingAction(null)
    },
    onError: () => setPendingAction(null),
  })

  const runClaude = (e: React.MouseEvent, action: 'summarize' | 'translate') => {
    e.stopPropagation()
    setPendingAction(action)
    claudeMutation.mutate(action)
  }

  const date = article.published_at
    ? new Date(article.published_at).toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' })
    : ''

  return (
    <div
      className={`group border-b border-gray-100 transition-colors ${
        selected ? 'bg-blue-50 border-l-2 border-l-blue-500' : !article.is_read ? 'bg-white hover:bg-gray-50' : 'bg-gray-50/50 hover:bg-gray-100/50'
      }`}
    >
      {/* メインコンテンツ行 */}
      <button onClick={onClick} className="w-full text-left px-4 py-3">
        <div className="flex items-start gap-2">
          {/* 未読インジケーター */}
          <span className={`mt-1.5 flex-shrink-0 w-2 h-2 rounded-full transition-colors ${
            !article.is_read ? 'bg-blue-500' : 'bg-transparent'
          }`} />

          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-1">
              <h3 className={`text-sm leading-snug ${!article.is_read ? 'font-semibold text-gray-900' : 'font-normal text-gray-600'}`}>
                {article.title ?? '(タイトルなし)'}
              </h3>
              {date && <span className="text-xs text-gray-400 flex-shrink-0 mt-0.5">{date}</span>}
            </div>
            {article.summary && (
              <p className="text-xs text-gray-500 line-clamp-2 mt-0.5">{article.summary}</p>
            )}
          </div>
        </div>
      </button>

      {/* アクションボタン行（ホバー時に表示） */}
      <div className="flex items-center gap-1 px-4 pb-2 opacity-0 group-hover:opacity-100 transition-opacity">
        <ActionButton
          label="要約"
          icon="✦"
          color="purple"
          loading={pendingAction === 'summarize'}
          onClick={e => runClaude(e, 'summarize')}
        />
        <ActionButton
          label="翻訳"
          icon="✦"
          color="indigo"
          loading={pendingAction === 'translate'}
          onClick={e => runClaude(e, 'translate')}
        />
        {article.is_read && (
          <ActionButton
            label="未読にする"
            icon="●"
            color="blue"
            loading={false}
            onClick={e => { e.stopPropagation(); onMarkAsUnread() }}
          />
        )}
      </div>

      {/* Claude 出力 */}
      {claudeMutation.isPending && (
        <div className="mx-4 mb-2 px-3 py-2 bg-purple-50 rounded text-xs text-purple-500 animate-pulse">
          {pendingAction === 'summarize' ? '要約' : '翻訳'}しています...
        </div>
      )}
      {claudeOutput && (
        <div className="mx-4 mb-2 px-3 py-2 bg-purple-50 border border-purple-100 rounded text-xs text-gray-700 leading-relaxed">
          <div className="flex justify-between items-center mb-1">
            <span className="text-purple-500 font-medium">
              ✦ {claudeOutput.action === 'summarize' ? '要約' : '翻訳'}
            </span>
            <button
              onClick={e => { e.stopPropagation(); setClaudeOutput(null) }}
              className="text-gray-400 hover:text-gray-600 text-xs"
            >
              ✕
            </button>
          </div>
          <p className="whitespace-pre-wrap">{claudeOutput.text}</p>
        </div>
      )}
      {claudeMutation.isError && (
        <div className="mx-4 mb-2 px-3 py-2 bg-red-50 rounded text-xs text-red-500">
          Claude の実行に失敗しました
        </div>
      )}
    </div>
  )
}

function ActionButton({ label, icon, color, loading, onClick }: {
  label: string
  icon: string
  color: 'purple' | 'indigo' | 'blue'
  loading: boolean
  onClick: (e: React.MouseEvent) => void
}) {
  const colors = {
    purple: 'bg-purple-100 text-purple-600 hover:bg-purple-200',
    indigo: 'bg-indigo-100 text-indigo-600 hover:bg-indigo-200',
    blue: 'bg-blue-100 text-blue-600 hover:bg-blue-200',
  }
  return (
    <button
      onClick={onClick}
      disabled={loading}
      className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium transition-colors disabled:opacity-50 ${colors[color]}`}
    >
      <span className={loading ? 'animate-pulse' : ''}>{icon}</span>
      {label}
    </button>
  )
}
