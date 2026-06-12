import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { articlesApi, feedsApi, type Article, type SortBy } from '../api/client'
import { queryKeys, invalidateArticles, invalidateFeedsAndArticles } from '../api/queryKeys'
import { useState } from 'react'

interface ArticleListProps {
  feedId: number | null
  groupId: number | null
  onSelectArticle: (article: Article) => void
  selectedArticleId: number | null
  onOpenSidebar?: () => void
  showSecretGroups?: boolean
}

export function ArticleList({ feedId, groupId, onSelectArticle, selectedArticleId, onOpenSidebar, showSecretGroups = false }: ArticleListProps) {
  const qc = useQueryClient()
  const [unreadOnly, setUnreadOnly] = useState(false)
  const [favoriteOnly, setFavoriteOnly] = useState(false)
  const [sortBy, setSortBy] = useState<SortBy>('published_at')

  const { data: articles = [], isLoading } = useQuery({
    queryKey: queryKeys.articleList({ feedId, groupId, unreadOnly, favoriteOnly, sortBy, showSecretGroups }),
    queryFn: () => articlesApi.list({ feedId: feedId ?? undefined, groupId: groupId ?? undefined, unreadOnly, favoriteOnly, sortBy, limit: 1000, offset: 0, includeSecret: showSecretGroups }),
  })

  const refresh = useMutation({
    // Why: ボタンは feedId != null のときだけ描画されるが、状態管理ミス時の NaN リクエスト
    // 発火を防ぐため早期 return で保険をかける。
    mutationFn: () => feedId == null ? Promise.resolve() : feedsApi.refresh(feedId),
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const markAsRead = useMutation({
    mutationFn: (id: number) => articlesApi.markAsRead(id),
    onSuccess: () => invalidateArticles(qc),
  })

  const markAsUnread = useMutation({
    mutationFn: (id: number) => articlesApi.markAsUnread(id),
    onSuccess: () => invalidateArticles(qc),
  })

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
              onChange={e => { setUnreadOnly(e.target.checked); if (e.target.checked) setFavoriteOnly(false) }}
              className="rounded"
            />
            未読のみ
          </label>
          <label className="flex items-center gap-2 text-sm text-yellow-600 dark:text-yellow-400 cursor-pointer">
            <input
              type="checkbox"
              checked={favoriteOnly}
              onChange={e => { setFavoriteOnly(e.target.checked); if (e.target.checked) setUnreadOnly(false) }}
              className="rounded"
            />
            ★ お気に入り
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

function ArticleCard({ article, selected, onClick, onMarkAsUnread }: {
  article: Article
  selected: boolean
  onClick: () => void
  onMarkAsUnread: () => void
}) {
  const qc = useQueryClient()

  const toggleFavorite = useMutation({
    mutationFn: () => article.is_favorite
      ? articlesApi.markAsUnfavorite(article.id)
      : articlesApi.markAsFavorite(article.id),
    onMutate: async () => {
      await qc.cancelQueries({ queryKey: queryKeys.articles })
      qc.setQueriesData<Article[]>({ queryKey: queryKeys.articles }, old =>
        old?.map(a => a.id === article.id ? { ...a, is_favorite: article.is_favorite ? 0 : 1 } : a)
      )
    },
    onSettled: () => invalidateArticles(qc),
  })

  const date = article.published_at ? formatDate(new Date(article.published_at)) : ''

  return (
    <div
      className={`group border-b border-gray-100 dark:border-gray-800 transition-colors ${
        selected
          ? 'bg-blue-50 dark:bg-blue-900/20 border-l-2 border-l-blue-500'
          : !article.is_read
            ? 'bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800'
            : 'bg-gray-50/50 dark:bg-gray-800/30 hover:bg-gray-100/50 dark:hover:bg-gray-800/60'
      }`}
    >
      {/* メインコンテンツ行 */}
      <button onClick={onClick} className="w-full text-left px-4 py-2">
        <div className="flex items-start gap-2">
          {/* 未読インジケーター */}
          <span className={`mt-1.5 flex-shrink-0 w-2 h-2 rounded-full transition-colors ${
            !article.is_read ? 'bg-blue-500' : 'bg-transparent'
          }`} />

          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-1">
              <h3 className={`text-sm leading-snug ${!article.is_read ? 'font-semibold text-gray-900 dark:text-gray-100' : 'font-normal text-gray-600 dark:text-gray-400'}`}>
                {article.title ?? '(タイトルなし)'}
              </h3>
              <div className="flex items-center gap-1 flex-shrink-0 mt-0.5">
                {article.is_favorite === 1 && (
                  <span className="text-[10px] text-yellow-500 dark:text-yellow-400 leading-4">★</span>
                )}
                {date && <span className="text-xs text-gray-400 dark:text-gray-500">{date}</span>}
              </div>
            </div>
            {article.summary && (
              <p className="text-xs text-gray-500 dark:text-gray-400 line-clamp-2 mt-0.5">{article.summary}</p>
            )}
          </div>
        </div>
      </button>

      {/* アクションボタン行（ホバー時に表示） */}
      <div className="hidden group-hover:flex items-center gap-1 px-4 pb-2">
        {article.is_read === 1 ? (
          <ActionButton
            label="未読にする"
            icon="○"
            color="blue"
            loading={false}
            onClick={e => { e.stopPropagation(); onMarkAsUnread() }}
          />
        ) : (
          <ActionButton
            label="既読にする"
            icon="●"
            color="gray"
            loading={false}
            onClick={e => { e.stopPropagation(); onClick() }}
          />
        )}
        <ActionButton
          label={article.is_favorite ? 'お気に入り解除' : 'お気に入り'}
          icon="★"
          color="yellow"
          loading={toggleFavorite.isPending}
          onClick={e => { e.stopPropagation(); toggleFavorite.mutate() }}
        />
      </div>
    </div>
  )
}

function ActionButton({ label, icon, color, loading, onClick }: {
  label: string
  icon: string
  color: 'blue' | 'gray' | 'yellow'
  loading: boolean
  onClick: (e: React.MouseEvent) => void
}) {
  const colors = {
    blue: 'bg-blue-100 dark:bg-blue-900/40 text-blue-600 dark:text-blue-400 hover:bg-blue-200 dark:hover:bg-blue-900/60',
    gray: 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600',
    yellow: 'bg-yellow-100 dark:bg-yellow-900/40 text-yellow-600 dark:text-yellow-400 hover:bg-yellow-200 dark:hover:bg-yellow-900/60',
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

function formatDate(date: Date): string {
  const now = new Date()
  const isToday = date.toDateString() === now.toDateString()
  const isThisYear = date.getFullYear() === now.getFullYear()

  if (isToday) {
    return date.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })
  }
  if (isThisYear) {
    return date.toLocaleString('ja-JP', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  }
  return date.toLocaleDateString('ja-JP', { year: 'numeric', month: 'short', day: 'numeric' })
}
