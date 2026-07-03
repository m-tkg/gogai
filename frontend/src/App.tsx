import { useState } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sidebar } from './components/Sidebar'
import { ArticleList } from './components/ArticleList'
import { ArticleDetail } from './components/ArticleDetail'
import { Settings } from './components/Settings'
import { useSelectionState } from './hooks/useSelectionState'
import { useDarkMode } from './hooks/useDarkMode'
import { useLocalStorageBool } from './hooks/useLocalStorageBool'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 1000 * 60 * 5 },
  },
})

function RssReader() {
  const selection = useSelectionState()
  const { darkMode, toggleDarkMode } = useDarkMode()
  const [sidebarOpen, toggleSidebar] = useLocalStorageBool('sidebarOpen', true)
  // シークレットグループの表示フラグ（保存されない）
  const [showSecretGroups, setShowSecretGroups] = useState(false)

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-white dark:bg-gray-900">
      <Sidebar
        selectedFeedId={selection.feedId}
        selectedGroupId={selection.groupId}
        onSelectFeed={selection.selectFeed}
        onSelectGroup={selection.selectGroup}
        darkMode={darkMode}
        onToggleDark={toggleDarkMode}
        onOpenSettings={selection.openSettings}
        showSettings={selection.showSettings}
        isOpen={sidebarOpen}
        onToggle={toggleSidebar}
        showSecretGroups={showSecretGroups}
      />
      {selection.showSettings ? (
        <Settings showSecretGroups={showSecretGroups} onToggleSecretGroups={() => setShowSecretGroups(v => !v)} />
      ) : (
        <>
          {/* 記事一覧: モバイルでは detail 表示中は隠す */}
          <div className={`border-r border-gray-200 dark:border-gray-700 flex-shrink-0 md:w-80 ${selection.mobileView === 'detail' ? 'hidden md:block' : 'flex-1 md:flex-initial'}`}>
            <ArticleList
              feedId={selection.feedId}
              groupId={selection.groupId}
              onSelectArticle={selection.selectArticle}
              selectedArticleId={selection.article?.id ?? null}
              onOpenSidebar={toggleSidebar}
              showSecretGroups={showSecretGroups}
            />
          </div>
          {/* 記事詳細: モバイルでは list 表示中は隠す */}
          <div className={`flex-1 min-w-0 ${selection.mobileView === 'list' ? 'hidden md:block' : 'block'}`}>
            <ArticleDetail article={selection.article} onBack={selection.backToList} />
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
