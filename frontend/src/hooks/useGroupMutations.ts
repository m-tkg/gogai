import { useMutation, useQueryClient } from '@tanstack/react-query'
import { groupsApi } from '../api/client'
import { invalidateGroups, invalidateFeedsAndArticles } from '../api/queryKeys'

// グループの CRUD・更新系 mutation を一箇所に集約する。
export function useGroupMutations() {
  const qc = useQueryClient()

  const addGroup = useMutation({
    mutationFn: (name: string) => groupsApi.create(name),
    onSuccess: () => invalidateGroups(qc),
  })

  const removeGroup = useMutation({
    mutationFn: (id: number) => groupsApi.remove(id),
    onSuccess: () => invalidateGroups(qc),
  })

  const toggleGroupSecret = useMutation({
    mutationFn: ({ id, name, isSecret }: { id: number; name: string; isSecret: number }) =>
      groupsApi.update(id, name, isSecret),
    onSuccess: () => invalidateGroups(qc),
  })

  const refreshGroup = useMutation({
    mutationFn: (id: number) => groupsApi.refresh(id),
    onSuccess: () => invalidateFeedsAndArticles(qc),
  })

  const reorderGroups = useMutation({
    mutationFn: (ids: number[]) => groupsApi.reorder(ids),
    onSuccess: () => invalidateGroups(qc),
  })

  return { addGroup, removeGroup, toggleGroupSecret, refreshGroup, reorderGroups }
}
