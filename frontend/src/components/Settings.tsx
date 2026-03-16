import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { settingsApi, adminApi, type UpdateCheck } from '../api/client'

const MIN = 3
const MAX = 180

export function Settings() {
  const qc = useQueryClient()
  const { data, isLoading } = useQuery({ queryKey: ['settings'], queryFn: settingsApi.get })
  const { data: updateCheck, isLoading: checkLoading, error: checkError } =
    useQuery<UpdateCheck>({ queryKey: ['update-check'], queryFn: adminApi.updateCheck })
  const [days, setDays] = useState<string>('')
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  const [confirmRestart, setConfirmRestart] = useState(false)
  const [restartOutput, setRestartOutput] = useState<string | null>(null)

  useEffect(() => {
    if (data) setDays(String(data.retention_days))
  }, [data])

  const restart = useMutation({
    mutationFn: () => adminApi.restart(),
    onSuccess: (data) => {
      setRestartOutput(data.output || '最新の状態です')
      setConfirmRestart(false)
    },
    onError: (e: { response?: { data?: { error?: string } } }) => {
      setRestartOutput(`エラー: ${e.response?.data?.error ?? '更新に失敗しました'}`)
      setConfirmRestart(false)
    },
  })

  const update = useMutation({
    mutationFn: () => settingsApi.update({ retention_days: Number(days) }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['settings'] })
      setError(null)
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
    },
    onError: (e: { response?: { data?: { error?: string } } }) => {
      setError(e.response?.data?.error ?? '保存に失敗しました')
    },
  })

  const validate = (): string | null => {
    const n = Number(days)
    if (!Number.isInteger(n) || isNaN(n)) return '整数で入力してください'
    if (n < MIN || n > MAX) return `${MIN} 以上 ${MAX} 以下で入力してください`
    return null
  }

  const handleSave = () => {
    const err = validate()
    if (err) { setError(err); return }
    update.mutate()
  }

  if (isLoading) return (
    <div className="flex-1 flex items-center justify-center text-gray-400 dark:text-gray-500">
      読み込み中...
    </div>
  )

  return (
    <div className="flex-1 p-8 bg-white dark:bg-gray-900 overflow-y-auto">
      <h2 className="text-xl font-bold text-gray-800 dark:text-gray-100 mb-6">設定</h2>

      <div className="max-w-md space-y-6">
        <section className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 space-y-3">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">記事の保持期間</h3>
          <p className="text-xs text-gray-500 dark:text-gray-400">
            指定した日数より古い記事を自動削除します。サーバー起動時と24時間ごとに実行されます。
          </p>
          <div className="flex items-center gap-2">
            <input
              type="number"
              min={MIN}
              max={MAX}
              value={days}
              onChange={e => { setDays(e.target.value); setError(null) }}
              onKeyDown={e => e.key === 'Enter' && handleSave()}
              className="w-24 px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded focus:outline-none focus:border-blue-400 bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            />
            <span className="text-sm text-gray-600 dark:text-gray-400">日</span>
            <span className="text-xs text-gray-400 dark:text-gray-500">（{MIN}〜{MAX}）</span>
          </div>

          {error && (
            <p className="text-xs text-red-500 dark:text-red-400">{error}</p>
          )}

          <button
            onClick={handleSave}
            disabled={update.isPending}
            className="px-4 py-1.5 text-sm bg-blue-500 hover:bg-blue-600 text-white rounded disabled:opacity-50 transition-colors"
          >
            {update.isPending ? '保存中...' : saved ? '✓ 保存しました' : '保存'}
          </button>
        </section>
        <section className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 space-y-3">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">アプリの更新</h3>

          {/* 更新確認ステータス */}
          {checkLoading && (
            <p className="text-xs text-gray-400 dark:text-gray-500 animate-pulse">更新を確認中...</p>
          )}
          {checkError && (
            <p className="text-xs text-red-500 dark:text-red-400">更新確認に失敗しました</p>
          )}
          {updateCheck && (
            <div className={`flex items-start gap-2 text-xs rounded px-3 py-2 ${
              updateCheck.hasUpdate
                ? 'bg-amber-50 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300'
                : 'bg-green-50 dark:bg-green-900/30 text-green-700 dark:text-green-300'
            }`}>
              <span>{updateCheck.hasUpdate ? '⬆' : '✓'}</span>
              <div className="space-y-0.5">
                <p className="font-medium">
                  {updateCheck.hasUpdate ? '更新があります' : '最新の状態です'}
                </p>
                <p className="font-mono opacity-75">
                  local:&nbsp; {updateCheck.local.slice(0, 7)}
                </p>
                {updateCheck.hasUpdate && (
                  <p className="font-mono opacity-75">
                    remote: {updateCheck.remote.slice(0, 7)}
                  </p>
                )}
              </div>
            </div>
          )}

          <p className="text-xs text-gray-500 dark:text-gray-400">
            git pull を実行して最新のコードを取得し、サービスを再起動します。
          </p>

          {restartOutput && (
            <pre className="text-xs bg-gray-900 text-green-400 rounded p-3 overflow-x-auto whitespace-pre-wrap">
              {restartOutput}
            </pre>
          )}

          {confirmRestart ? (
            <div className="space-y-2">
              <p className="text-sm text-amber-600 dark:text-amber-400 font-medium">
                本当に更新して再起動しますか？
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => restart.mutate()}
                  disabled={restart.isPending}
                  className="px-4 py-1.5 text-sm bg-red-500 hover:bg-red-600 text-white rounded disabled:opacity-50 transition-colors"
                >
                  {restart.isPending ? '実行中...' : '実行する'}
                </button>
                <button
                  onClick={() => setConfirmRestart(false)}
                  disabled={restart.isPending}
                  className="px-4 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-300 disabled:opacity-50 transition-colors"
                >
                  キャンセル
                </button>
              </div>
            </div>
          ) : (
            <button
              onClick={() => { setRestartOutput(null); setConfirmRestart(true) }}
              className="px-4 py-1.5 text-sm bg-amber-500 hover:bg-amber-600 text-white rounded transition-colors"
            >
              ↻ git pull &amp;&amp; 再起動
            </button>
          )}
        </section>
      </div>
    </div>
  )
}
