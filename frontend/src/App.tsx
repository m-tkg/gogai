import { useState, useEffect } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sidebar } from './components/Sidebar'
import { ArticleList } from './components/ArticleList'
import { ArticleDetail } from './components/ArticleDetail'
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
  const [darkMode, setDarkMode] = useState<boolean>(() => {
    const saved = localStorage.getItem('darkMode')
    if (saved !== null) return saved === 'true'
    return window.matchMedia('(prefers-color-scheme: dark)').matches
  })

  useEffect(() => {
    document.documentElement.classList.toggle('dark', darkMode)
    localStorage.setItem('darkMode', String(darkMode))
  }, [darkMode])

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-white dark:bg-gray-900">
      <Sidebar
        selectedFeedId={selectedFeedId}
        selectedGroupId={selectedGroupId}
        onSelectFeed={setSelectedFeedId}
        onSelectGroup={setSelectedGroupId}
        darkMode={darkMode}
        onToggleDark={() => setDarkMode(d => !d)}
      />
      <div className="w-80 border-r border-gray-200 dark:border-gray-700 flex-shrink-0">
        <ArticleList
          feedId={selectedFeedId}
          groupId={selectedGroupId}
          onSelectArticle={setSelectedArticle}
          selectedArticleId={selectedArticle?.id ?? null}
        />
      </div>
      <div className="flex-1 min-w-0">
        <ArticleDetail article={selectedArticle} />
      </div>
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
