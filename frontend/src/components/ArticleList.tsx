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
          />
        ))}
      </div>
    </div>
  )
}

function ArticleCard({ article, selected, onClick }: {
  article: Article
  selected: boolean
  onClick: () => void
}) {
  const date = article.published_at
    ? new Date(article.published_at).toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' })
    : ''

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-4 py-3 border-b border-gray-100 hover:bg-gray-50 transition-colors ${
        selected ? 'bg-blue-50 border-l-2 border-l-blue-500' : ''
      } ${!article.is_read ? 'bg-white' : 'bg-gray-50/50'}`}
    >
      <div className="flex items-start gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-0.5">
            {!article.is_read && (
              <span className="inline-block w-2 h-2 rounded-full bg-blue-500 flex-shrink-0 mt-1" />
            )}
            <h3 className={`text-sm leading-snug truncate ${!article.is_read ? 'font-semibold text-gray-900' : 'font-normal text-gray-600'}`}>
              {article.title ?? '(タイトルなし)'}
            </h3>
          </div>
          {article.summary && (
            <p className="text-xs text-gray-500 line-clamp-2 mt-0.5">
              {article.summary}
            </p>
          )}
          {date && (
            <p className="text-xs text-gray-400 mt-1">{date}</p>
          )}
        </div>
      </div>
    </button>
  )
}
