import type { Article } from '../../api/client'

interface ArticleCardProps {
  article: Article
  selected: boolean
  onClick: () => void
  onMarkAsUnread: () => void
}

export function ArticleCard({ article, selected, onClick, onMarkAsUnread }: ArticleCardProps) {
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
            onClick={e => { e.stopPropagation(); onMarkAsUnread() }}
          />
        ) : (
          <ActionButton
            label="既読にする"
            icon="●"
            color="gray"
            onClick={e => { e.stopPropagation(); onClick() }}
          />
        )}
      </div>
    </div>
  )
}

function ActionButton({ label, icon, color, onClick }: {
  label: string
  icon: string
  color: 'blue' | 'gray'
  onClick: (e: React.MouseEvent) => void
}) {
  const colors = {
    blue: 'bg-blue-100 dark:bg-blue-900/40 text-blue-600 dark:text-blue-400 hover:bg-blue-200 dark:hover:bg-blue-900/60',
    gray: 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600',
  }
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium transition-colors ${colors[color]}`}
    >
      <span>{icon}</span>
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
