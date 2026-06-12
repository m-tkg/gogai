import { useMutation, useQueryClient } from '@tanstack/react-query'
import { feedsApi } from '../api/client'
import { invalidateFeeds, invalidateFeedsAndArticles } from '../api/queryKeys'

export interface UpdateFeedInput {
  id: number
  data: { url?: string; title?: string; groupId?: number | null }
}

// フィードの CRUD・更新系 mutation を一箇所に集約する。
// UI 状態（フォームのクリア等）は呼び出し側が mutate の onSuccess/onError で扱う。
export function useFeedMutations() {
  const qc = useQueryClient()

  const addFeed = useMutation({
    mutationFn: ({ url, groupId }: { url: string; groupId?: number }) => feedsApi.create(url, groupId),
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const removeFeed = useMutation({
    mutationFn: (id: number) => feedsApi.remove(id),
    onSuccess: () => invalidateFeeds(qc),
  })

  const updateFeed = useMutation({
    mutationFn: ({ id, data }: UpdateFeedInput) => feedsApi.update(id, data),
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const refreshFeed = useMutation({
    mutationFn: (id: number) => feedsApi.refresh(id),
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const refreshAllFeeds = useMutation({
    mutationFn: feedsApi.refreshAll,
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const reorderFeeds = useMutation({
    mutationFn: (ids: number[]) => feedsApi.reorder(ids),
    onSuccess: () => invalidateFeeds(qc),
  })

  return { addFeed, removeFeed, updateFeed, refreshFeed, refreshAllFeeds, reorderFeeds }
}
