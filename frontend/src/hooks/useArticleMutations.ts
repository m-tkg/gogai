import { useMutation, useQueryClient } from '@tanstack/react-query'
import { articlesApi, feedsApi } from '../api/client'
import { invalidateArticles, invalidateFeedsAndArticles } from '../api/queryKeys'

// 記事一覧の更新・既読/未読トグル系 mutation を一箇所に集約する。
export function useArticleMutations(feedId: number | null) {
  const qc = useQueryClient()

  const refresh = useMutation({
    // Why: ボタンは feedId != null のときだけ描画されるが、状態管理ミス時の NaN リクエスト
    // 発火を防ぐため早期 return で保険をかける。
    mutationFn: () => feedId == null ? Promise.resolve() : feedsApi.refresh(feedId),
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const markAsRead = useMutation({
    mutationFn: (id: number) => articlesApi.markAsRead(id),
    onSuccess: () => invalidateArticles(qc),
  })

  const markAsUnread = useMutation({
    mutationFn: (id: number) => articlesApi.markAsUnread(id),
    onSuccess: () => invalidateArticles(qc),
  })

  return { refresh, markAsRead, markAsUnread }
}
