import { useState } from 'react'

// localStorage で永続化する boolean 状態（サイドバー開閉など）
export function useLocalStorageBool(key: string, defaultValue: boolean): [boolean, () => void] {
  const [value, setValue] = useState<boolean>(() => {
    const saved = localStorage.getItem(key)
    return saved !== null ? saved === 'true' : defaultValue
  })

  const toggle = () => {
    setValue(prev => {
      const next = !prev
      localStorage.setItem(key, String(next))
      return next
    })
  }

  return [value, toggle]
}
