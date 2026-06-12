import { useState } from 'react'
import type { Article } from '../api/client'

export type MobileView = 'list' | 'detail'

// フィード/グループ/記事の選択と画面遷移（設定表示・モバイルパネル切替）を一元管理する。
// 「フィードを選んだら記事選択と設定をリセットして一覧へ戻る」といった
// 複合的な状態遷移をここに閉じ込め、コンポーネント側での setState の組み合わせ漏れを防ぐ。
export function useSelectionState() {
  const [feedId, setFeedId] = useState<number | null>(null)
  const [groupId, setGroupId] = useState<number | null>(null)
  const [article, setArticle] = useState<Article | null>(null)
  const [showSettings, setShowSettings] = useState(false)
  // モバイルでは一度に一パネルのみ表示する（list: 記事一覧, detail: 記事詳細）
  const [mobileView, setMobileView] = useState<MobileView>('list')

  const resetToList = () => {
    setArticle(null)
    setShowSettings(false)
    setMobileView('list')
  }

  const selectFeed = (id: number | null) => {
    setFeedId(id)
    resetToList()
  }

  const selectGroup = (id: number | null) => {
    setGroupId(id)
    resetToList()
  }

  const selectArticle = (a: Article) => {
    setArticle(a)
    setMobileView('detail')
  }

  const backToList = () => setMobileView('list')
  const openSettings = () => setShowSettings(true)

  return { feedId, groupId, article, showSettings, mobileView, selectFeed, selectGroup, selectArticle, backToList, openSettings }
}
