import { useState, useEffect } from 'react'
import { useMutation } from '@tanstack/react-query'
import DOMPurify from 'dompurify'
import { articlesApi, type Article } from '../api/client'

interface ArticleDetailProps {
  article: Article | null
  onBack?: () => void
}

export function ArticleDetail({ article, onBack }: ArticleDetailProps) {
  const [claudeOutput, setClaudeOutput] = useState<string | null>(null)
  const [claudeAction, setClaudeAction] = useState<'summarize' | 'translate' | null>(null)
  const [audioUrl, setAudioUrl] = useState<string | null>(null)
  const [audioInput, setAudioInput] = useState('')

  const claudeMutation = useMutation({
    mutationFn: ({ id, action }: { id: number; action: 'summarize' | 'translate' }) =>
      articlesApi.claude(id, action),
    onSuccess: (data) => setClaudeOutput(data.output),
  })

  const setAudioMutation = useMutation({
    mutationFn: ({ id, url }: { id: number; url: string }) => articlesApi.setAudio(id, url),
    onSuccess: (data) => {
      setAudioUrl(data.ai_audio_url)
      setAudioInput('')
    },
  })

  const clearAudioMutation = useMutation({
    mutationFn: (id: number) => articlesApi.clearAudio(id),
    onSuccess: () => setAudioUrl(null),
  })

  const runClaude = (action: 'summarize' | 'translate') => {
    if (!article) return
    setClaudeAction(action)
    setClaudeOutput(null)
    claudeMutation.mutate({ id: article.id, action })
  }

  const openNotebookLM = () => {
    if (article?.link) navigator.clipboard.writeText(article.link).catch(() => {})
    window.open('https://notebooklm.google.com/', '_blank', 'noopener,noreferrer')
  }

  const submitAudioUrl = () => {
    if (!article) return
    const trimmed = audioInput.trim()
    if (!trimmed) return
    setAudioMutation.mutate({ id: article.id, url: trimmed })
  }

  // 記事が切り替わったらClaudeの出力と音声 URL 入力をリセット
  useEffect(() => {
    setClaudeOutput(null)
    setClaudeAction(null)
    setAudioUrl(article?.ai_audio_url ?? null)
    setAudioInput('')
  }, [article?.id, article?.ai_audio_url])

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
            <button
              onClick={openNotebookLM}
              className="px-3 py-1.5 text-xs bg-emerald-100 dark:bg-emerald-900/40 text-emerald-700 dark:text-emerald-300 rounded-full hover:bg-emerald-200 dark:hover:bg-emerald-900/60 font-medium"
              title="記事 URL を Clipboard にコピーして NotebookLM を開く"
            >
              ♪ NotebookLM
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

        {/* NotebookLM 音声解説 */}
        <div className="p-4 bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800 rounded-lg">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-emerald-700 dark:text-emerald-300">♪ NotebookLM 音声解説</span>
            {audioUrl && (
              <button
                onClick={() => article && clearAudioMutation.mutate(article.id)}
                disabled={clearAudioMutation.isPending}
                className="text-xs text-emerald-500 hover:text-emerald-700 dark:hover:text-emerald-200 disabled:opacity-50"
              >
                クリア
              </button>
            )}
          </div>
          {audioUrl ? (
            <iframe
              src={audioUrl}
              title="NotebookLM Audio Overview"
              className="w-full h-40 rounded border border-emerald-200 dark:border-emerald-800 bg-white"
              allow="autoplay"
            />
          ) : (
            <div className="space-y-2">
              <p className="text-xs text-emerald-700/80 dark:text-emerald-300/80">
                NotebookLM で生成した Audio Overview の共有 URL を貼り付けてください。
              </p>
              <div className="flex gap-2">
                <input
                  type="url"
                  value={audioInput}
                  onChange={(e) => setAudioInput(e.target.value)}
                  placeholder="https://notebooklm.google.com/notebook/..."
                  className="flex-1 px-3 py-1.5 text-xs rounded border border-emerald-300 dark:border-emerald-700 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                />
                <button
                  onClick={submitAudioUrl}
                  disabled={setAudioMutation.isPending || !audioInput.trim()}
                  className="px-3 py-1.5 text-xs bg-emerald-600 text-white rounded hover:bg-emerald-700 disabled:opacity-50"
                >
                  保存
                </button>
              </div>
              {setAudioMutation.isError && (
                <p className="text-xs text-red-600 dark:text-red-400">URL の保存に失敗しました。</p>
              )}
            </div>
          )}
        </div>

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

// Why: 自前の正規表現サニタイズは属性ベース XSS（<img src=x onerror=...> など）を通すため、
// DOMPurify に置き換え。<a> へ target="_blank" rel="noopener noreferrer" 付与は afterSanitizeAttributes
// フックで実施する。
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A') {
    node.setAttribute('target', '_blank')
    node.setAttribute('rel', 'noopener noreferrer')
  }
})

function sanitizeHtml(html: string): string {
  return DOMPurify.sanitize(html)
}
