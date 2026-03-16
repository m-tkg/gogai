import { useState, useEffect } from 'react'
import { useMutation } from '@tanstack/react-query'
import { articlesApi, type Article } from '../api/client'

interface ArticleDetailProps {
  article: Article | null
  onBack?: () => void
}

export function ArticleDetail({ article, onBack }: ArticleDetailProps) {
  const [claudeOutput, setClaudeOutput] = useState<string | null>(null)
  const [claudeAction, setClaudeAction] = useState<'summarize' | 'translate' | null>(null)

  const claudeMutation = useMutation({
    mutationFn: ({ id, action }: { id: number; action: 'summarize' | 'translate' }) =>
      articlesApi.claude(id, action),
    onSuccess: (data) => setClaudeOutput(data.output),
  })

  const runClaude = (action: 'summarize' | 'translate') => {
    if (!article) return
    setClaudeAction(action)
    setClaudeOutput(null)
    claudeMutation.mutate({ id: article.id, action })
  }

  // 記事が切り替わったらClaudeの出力をリセット
  useEffect(() => {
    setClaudeOutput(null)
    setClaudeAction(null)
  }, [article?.id])

  if (!article) {
    return (
      <div className="flex items-center justify-center h-full text-gray-400 dark:text-gray-500 bg-white dark:bg-gray-900">
        記事を選択してください
      </div>
    )
  }

  const date = article.published_at
    ? new Date(article.published_at).toLocaleDateString('ja-JP', {
        year: 'numeric', month: 'long', day: 'numeric',
      })
    : null

  return (
    <article className="flex flex-col h-screen overflow-hidden bg-white dark:bg-gray-900">
      <header className="px-4 py-4 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900">
        {/* モバイル用戻るボタン */}
        {onBack && (
          <button
            onClick={onBack}
            className="md:hidden mb-3 flex items-center gap-1 text-sm text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300"
            aria-label="記事一覧に戻る"
          >
            ← 記事一覧
          </button>
        )}
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 leading-snug mb-2">
          {article.title ?? '(タイトルなし)'}
        </h2>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            {date && <span className="text-sm text-gray-500 dark:text-gray-400">{date}</span>}
            {article.link && (
              <a
                href={article.link}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-blue-600 dark:text-blue-400 hover:underline"
              >
                元記事を開く ↗
              </a>
            )}
          </div>
          {/* Claude アクションボタン */}
          <div className="flex items-center gap-2">
            <button
              onClick={() => runClaude('summarize')}
              disabled={claudeMutation.isPending}
              className="px-3 py-1.5 text-xs bg-purple-100 dark:bg-purple-900/40 text-purple-700 dark:text-purple-300 rounded-full hover:bg-purple-200 dark:hover:bg-purple-900/60 disabled:opacity-50 font-medium"
              title="Claude で要約"
            >
              {claudeMutation.isPending && claudeAction === 'summarize' ? '要約中...' : '✦ 要約'}
            </button>
            <button
              onClick={() => runClaude('translate')}
              disabled={claudeMutation.isPending}
              className="px-3 py-1.5 text-xs bg-indigo-100 dark:bg-indigo-900/40 text-indigo-700 dark:text-indigo-300 rounded-full hover:bg-indigo-200 dark:hover:bg-indigo-900/60 disabled:opacity-50 font-medium"
              title="Claude で日本語翻訳"
            >
              {claudeMutation.isPending && claudeAction === 'translate' ? '翻訳中...' : '✦ 翻訳'}
            </button>
          </div>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
        {/* Claude出力 */}
        {claudeMutation.isPending && (
          <div className="p-4 bg-purple-50 dark:bg-purple-900/30 border border-purple-200 dark:border-purple-800 rounded-lg">
            <div className="flex items-center gap-2 text-purple-600 dark:text-purple-400 text-sm">
              <span className="animate-pulse">✦</span>
              Claude が{claudeAction === 'summarize' ? '要約' : '翻訳'}しています...
            </div>
          </div>
        )}

        {claudeOutput && (
          <div className="p-4 bg-purple-50 dark:bg-purple-900/30 border border-purple-200 dark:border-purple-800 rounded-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-medium text-purple-600 dark:text-purple-400">
                ✦ Claude による{claudeAction === 'summarize' ? '要約' : '翻訳'}
              </span>
              <button
                onClick={() => setClaudeOutput(null)}
                className="text-xs text-purple-400 hover:text-purple-600 dark:hover:text-purple-300"
              >
                閉じる
              </button>
            </div>
            <p className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap leading-relaxed">
              {claudeOutput}
            </p>
          </div>
        )}

        {claudeMutation.isError && (
          <div className="p-3 bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            Claude の実行に失敗しました。CLIがインストールされているか確認してください。
          </div>
        )}

        {/* 記事本文 */}
        {article.content ? (
          <ArticleContent html={sanitizeHtml(article.content)} />
        ) : article.summary ? (
          <p className="text-gray-800 dark:text-gray-200 leading-relaxed">{article.summary}</p>
        ) : (
          <p className="text-gray-400 dark:text-gray-500 text-sm">本文がありません。元記事を開いてください。</p>
        )}
      </div>
    </article>
  )
}

// 100行超えたら省略して展開ボタンを表示
const LINE_HEIGHT_PX = 24 // 1.5rem
const MAX_LINES = 100
const MAX_HEIGHT = LINE_HEIGHT_PX * MAX_LINES

function ArticleContent({ html }: { html: string }) {
  const [expanded, setExpanded] = useState(false)
  const [overflows, setOverflows] = useState(false)
  const ref = (node: HTMLDivElement | null) => {
    if (node) setOverflows(node.scrollHeight > MAX_HEIGHT + 10)
  }

  return (
    <div>
      <div
        ref={ref}
        style={!expanded ? { maxHeight: `${MAX_HEIGHT}px`, overflow: 'hidden' } : undefined}
        className="text-sm text-gray-800 dark:text-gray-200 leading-6 [&_img]:max-w-full [&_a]:text-blue-600 dark:[&_a]:text-blue-400 [&_a]:underline [&_pre]:overflow-x-auto [&_pre]:bg-gray-100 dark:[&_pre]:bg-gray-800 [&_pre]:p-3 [&_pre]:rounded [&_blockquote]:border-l-4 [&_blockquote]:border-gray-300 dark:[&_blockquote]:border-gray-600 [&_blockquote]:pl-4 [&_blockquote]:text-gray-600 dark:[&_blockquote]:text-gray-400"
        dangerouslySetInnerHTML={{ __html: html }}
      />
      {overflows && (
        <button
          onClick={() => setExpanded(e => !e)}
          className="mt-3 text-xs text-blue-600 hover:underline"
        >
          {expanded ? '折りたたむ ↑' : '続きを読む ↓'}
        </button>
      )}
    </div>
  )
}

// 基本的なHTMLサニタイズ（scriptタグ除去）＋外部リンクを新しいタブで開く
function sanitizeHtml(html: string): string {
  return html
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/on\w+="[^"]*"/g, '')
    .replace(/on\w+='[^']*'/g, '')
    .replace(/<a\s/gi, '<a target="_blank" rel="noopener noreferrer" ')
}
