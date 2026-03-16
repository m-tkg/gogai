import { useState, useEffect } from 'react'
import { useMutation } from '@tanstack/react-query'
import { articlesApi, type Article } from '../api/client'

interface ArticleDetailProps {
  article: Article | null
}

export function ArticleDetail({ article }: ArticleDetailProps) {
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
      <div className="flex items-center justify-center h-full text-gray-400">
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
    <article className="flex flex-col h-screen overflow-hidden">
      <header className="px-6 py-4 border-b border-gray-200 bg-white">
        <h2 className="text-lg font-semibold text-gray-900 leading-snug mb-2">
          {article.title ?? '(タイトルなし)'}
        </h2>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            {date && <span className="text-sm text-gray-500">{date}</span>}
            {article.link && (
              <a
                href={article.link}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-blue-600 hover:underline"
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
              className="px-3 py-1.5 text-xs bg-purple-100 text-purple-700 rounded-full hover:bg-purple-200 disabled:opacity-50 font-medium"
              title="Claude で要約"
            >
              {claudeMutation.isPending && claudeAction === 'summarize' ? '要約中...' : '✦ 要約'}
            </button>
            <button
              onClick={() => runClaude('translate')}
              disabled={claudeMutation.isPending}
              className="px-3 py-1.5 text-xs bg-indigo-100 text-indigo-700 rounded-full hover:bg-indigo-200 disabled:opacity-50 font-medium"
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
          <div className="p-4 bg-purple-50 border border-purple-200 rounded-lg">
            <div className="flex items-center gap-2 text-purple-600 text-sm">
              <span className="animate-pulse">✦</span>
              Claude が{claudeAction === 'summarize' ? '要約' : '翻訳'}しています...
            </div>
          </div>
        )}

        {claudeOutput && (
          <div className="p-4 bg-purple-50 border border-purple-200 rounded-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-medium text-purple-600">
                ✦ Claude による{claudeAction === 'summarize' ? '要約' : '翻訳'}
              </span>
              <button
                onClick={() => setClaudeOutput(null)}
                className="text-xs text-purple-400 hover:text-purple-600"
              >
                閉じる
              </button>
            </div>
            <p className="text-sm text-gray-800 whitespace-pre-wrap leading-relaxed">
              {claudeOutput}
            </p>
          </div>
        )}

        {claudeMutation.isError && (
          <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-600">
            Claude の実行に失敗しました。CLIがインストールされているか確認してください。
          </div>
        )}

        {/* 記事本文 */}
        {article.content ? (
          <div
            className="prose prose-sm max-w-none text-gray-800 leading-relaxed"
            dangerouslySetInnerHTML={{ __html: sanitizeHtml(article.content) }}
          />
        ) : article.summary ? (
          <p className="text-gray-800 leading-relaxed">{article.summary}</p>
        ) : (
          <p className="text-gray-400 text-sm">本文がありません。元記事を開いてください。</p>
        )}
      </div>
    </article>
  )
}

// 基本的なHTMLサニタイズ（scriptタグ除去）
function sanitizeHtml(html: string): string {
  return html
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/on\w+="[^"]*"/g, '')
    .replace(/on\w+='[^']*'/g, '')
}
