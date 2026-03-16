import { useState, useEffect } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sidebar } from './components/Sidebar'
import { ArticleList } from './components/ArticleList'
import { ArticleDetail } from './components/ArticleDetail'
import { Settings } from './components/Settings'
import type { Article } from './api/client'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 1000 * 60 * 5 },
  },
})

function RssReader() {
  const [selectedFeedId, setSelectedFeedId] = useState<number | null>(null)
  const [selectedGroupId, setSelectedGroupId] = useState<number | null>(null)
  const [selectedArticle, setSelectedArticle] = useState<Article | null>(null)
  const [showSettings, setShowSettings] = useState(false)
  // モバイルでは一度に一パネルのみ表示する（list: 記事一覧, detail: 記事詳細）
  const [mobileView, setMobileView] = useState<'list' | 'detail'>('list')
  // サイドバー開閉状態（localStorage で永続化）
  const [sidebarOpen, setSidebarOpen] = useState<boolean>(() => {
    const saved = localStorage.getItem('sidebarOpen')
    return saved !== null ? saved === 'true' : true
  })
  const [darkMode, setDarkMode] = useState<boolean>(() => {
    const saved = localStorage.getItem('darkMode')
    if (saved !== null) return saved === 'true'
    return window.matchMedia('(prefers-color-scheme: dark)').matches
  })

  useEffect(() => {
    document.documentElement.classList.toggle('dark', darkMode)
    localStorage.setItem('darkMode', String(darkMode))
  }, [darkMode])

  const toggleSidebar = () => {
    const next = !sidebarOpen
    setSidebarOpen(next)
    localStorage.setItem('sidebarOpen', String(next))
  }

  const handleSelectArticle = (article: Article) => {
    setSelectedArticle(article)
    setMobileView('detail')
  }

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-white dark:bg-gray-900">
      <Sidebar
        selectedFeedId={selectedFeedId}
        selectedGroupId={selectedGroupId}
        onSelectFeed={(id) => { setSelectedFeedId(id); setShowSettings(false); setMobileView('list') }}
        onSelectGroup={(id) => { setSelectedGroupId(id); setShowSettings(false); setMobileView('list') }}
        darkMode={darkMode}
        onToggleDark={() => setDarkMode(d => !d)}
        onOpenSettings={() => setShowSettings(true)}
        showSettings={showSettings}
        isOpen={sidebarOpen}
        onToggle={toggleSidebar}
      />
      {showSettings ? (
        <Settings />
      ) : (
        <>
          {/* 記事一覧: モバイルでは detail 表示中は隠す */}
          <div className={`border-r border-gray-200 dark:border-gray-700 flex-shrink-0 md:w-80 ${mobileView === 'detail' ? 'hidden md:block' : 'flex-1 md:flex-initial'}`}>
            <ArticleList
              feedId={selectedFeedId}
              groupId={selectedGroupId}
              onSelectArticle={handleSelectArticle}
              selectedArticleId={selectedArticle?.id ?? null}
              onOpenSidebar={toggleSidebar}
            />
          </div>
          {/* 記事詳細: モバイルでは list 表示中は隠す */}
          <div className={`flex-1 min-w-0 ${mobileView === 'list' ? 'hidden md:block' : 'block'}`}>
            <ArticleDetail article={selectedArticle} onBack={() => setMobileView('list')} />
          </div>
        </>
      )}
    </div>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <RssReader />
    </QueryClientProvider>
  )
}
