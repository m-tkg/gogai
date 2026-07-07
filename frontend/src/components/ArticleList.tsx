import { useQuery } from '@tanstack/react-query'
import { articlesApi, type Article, type SortBy } from '../api/client'
import { queryKeys } from '../api/queryKeys'
import { useState } from 'react'
import { ArticleCard } from './articles/ArticleCard'
import { useArticleMutations } from '../hooks/useArticleMutations'

interface ArticleListProps {
  feedId: number | null
  groupId: number | null
  onSelectArticle: (article: Article) => void
  selectedArticleId: number | null
  onOpenSidebar?: () => void
  showSecretGroups?: boolean
}

export function ArticleList({ feedId, groupId, onSelectArticle, selectedArticleId, onOpenSidebar, showSecretGroups = false }: ArticleListProps) {
  const [unreadOnly, setUnreadOnly] = useState(false)
  const [sortBy, setSortBy] = useState<SortBy>('published_at')

  const { data: articles = [], isLoading } = useQuery({
    queryKey: queryKeys.articleList({ feedId, groupId, unreadOnly, sortBy, showSecretGroups }),
    queryFn: () => articlesApi.list({ feedId: feedId ?? undefined, groupId: groupId ?? undefined, unreadOnly, sortBy, limit: 1000, offset: 0, includeSecret: showSecretGroups }),
  })

  const { refresh, markAsRead, markAsUnread } = useArticleMutations(feedId)

  const handleSelect = (article: Article) => {
    onSelectArticle(article)
    if (!article.is_read) {
      markAsRead.mutate(article.id)
    }
  }

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-white dark:bg-gray-900">
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900">
        <div className="flex items-center gap-2">
          {/* モバイル用ハンバーガーメニューボタン */}
          {onOpenSidebar && (
            <button
              onClick={onOpenSidebar}
              className="md:hidden p-1 rounded text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800"
              aria-label="メニューを開く"
            >
              ☰
            </button>
          )}
          <label className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 cursor-pointer">
            <input
              type="checkbox"
              checked={unreadOnly}
              onChange={e => setUnreadOnly(e.target.checked)}
              className="rounded"
            />
            未読のみ
          </label>
          <select
            value={sortBy}
            onChange={e => setSortBy(e.target.value as SortBy)}
            className="text-xs text-gray-600 dark:text-gray-400 bg-transparent border border-gray-200 dark:border-gray-700 rounded px-1 py-0.5 cursor-pointer"
            aria-label="ソート順"
          >
            <option value="published_at">配信日順</option>
            <option value="read_at">既読日時順</option>
          </select>
        </div>
        {feedId && (
          <button
            onClick={() => refresh.mutate()}
            disabled={refresh.isPending}
            className="text-sm text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 disabled:opacity-50"
          >
            {refresh.isPending ? '更新中...' : '↻ 更新'}
          </button>
        )}
      </div>

      <div className="flex-1 overflow-y-auto">
        {isLoading && (
          <div className="flex items-center justify-center h-32 text-gray-400 dark:text-gray-500">
            読み込み中...
          </div>
        )}
        {!isLoading && articles.length === 0 && (
          <div className="flex items-center justify-center h-32 text-gray-400 dark:text-gray-500 text-sm">
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
