import { useEffect, useState } from 'react'

// ダークモード状態。初期値は localStorage → システム設定の優先順。
// 変更時に document.documentElement の dark クラスと localStorage を同期する。
export function useDarkMode() {
  const [darkMode, setDarkMode] = useState<boolean>(() => {
    const saved = localStorage.getItem('darkMode')
    if (saved !== null) return saved === 'true'
    return window.matchMedia('(prefers-color-scheme: dark)').matches
  })

  useEffect(() => {
    document.documentElement.classList.toggle('dark', darkMode)
    localStorage.setItem('darkMode', String(darkMode))
  }, [darkMode])

  const toggleDarkMode = () => setDarkMode(d => !d)

  return { darkMode, toggleDarkMode }
}
