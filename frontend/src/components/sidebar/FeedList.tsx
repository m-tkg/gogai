import type { Group, Feed } from '../../api/client'
import type { useFeedMutations } from '../../hooks/useFeedMutations'
import type { useDragReorder } from '../../hooks/useDragReorder'
import { FeedItem } from './FeedItem'

export type FeedMutations = ReturnType<typeof useFeedMutations>
export type DragReorder = ReturnType<typeof useDragReorder<Feed>>

interface FeedListProps {
  feeds: Feed[]
  groups: Group[]
  selectedFeedId: number | null
  onSelectFeed: (id: number) => void
  feedMutations: FeedMutations
  feedDnd: DragReorder
}

// FeedItem の並びを描画する（グループ内・グループなし共通）
export function FeedList({ feeds, groups, selectedFeedId, onSelectFeed, feedMutations, feedDnd }: FeedListProps) {
  const { removeFeed, refreshFeed, updateFeed } = feedMutations
  return (
    <>
      {feeds.map((feed) => (
        <FeedItem
          key={feed.id}
          feed={feed}
          groups={groups}
          selected={selectedFeedId === feed.id}
          onSelect={() => onSelectFeed(feed.id)}
          onRemove={(onSuccess) => removeFeed.mutate(feed.id, { onSuccess })}
          onRefresh={() => refreshFeed.mutate(feed.id)}
          onUpdate={(data, onSuccess, onError) => updateFeed.mutate({ id: feed.id, data }, { onSuccess, onError })}
          isRefreshing={refreshFeed.isPending && refreshFeed.variables === feed.id}
          isUpdating={updateFeed.isPending && updateFeed.variables?.id === feed.id}
          isDragging={feedDnd.dragId === feed.id}
          isDragOver={feedDnd.dragOverId === feed.id}
          onDragStart={() => feedDnd.handleDragStart(feed.id)}
          onDragOver={(e) => feedDnd.handleDragOver(e, feed.id)}
          onDrop={() => feedDnd.handleDrop(feeds)}
          onDragEnd={feedDnd.handleDragEnd}
        />
      ))}
    </>
  )
}
